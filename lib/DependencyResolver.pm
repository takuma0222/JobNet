package DependencyResolver;
use strict;
use warnings;
use File::Basename;
use LanguageDetector;
use Analyzer::Sh;
use Analyzer::Csh;
use Analyzer::Cobol;
use Analyzer::Plsql;

sub new {
    my ($class, %args) = @_;
    my $self = {
        file_mapper    => $args{file_mapper},
        var_resolver   => $args{var_resolver},
        logger         => $args{logger},
        max_depth      => $args{max_depth} // 10,
        encoding       => $args{encoding} // 'utf-8',
        analyzed_files => {},  # Track analyzed files to prevent infinite loops
        language_detector => LanguageDetector->new(),
    };
    bless $self, $class;
    return $self;
}

sub analyzed_files {
    my ($self) = @_;
    return $self->{analyzed_files};
}

sub resolve {
    my ($self, $entry_file) = @_;
    
    # Reset analyzed files for each entry point to ensure complete analysis
    $self->{analyzed_files} = {};
    
    # Clear script-defined variables for fresh analysis
    if ($self->{var_resolver}) {
        $self->{var_resolver}->clear_script_variables();
    }
    
    my $all_dependencies = [];
    my $all_file_io = [];
    my $all_db_ops = [];
    
    $self->_resolve_recursive(
        $entry_file,
        $entry_file,
        0,
        $all_dependencies,
        $all_file_io,
        $all_db_ops,
        'entry'  # call_type: entry point (clear variables)
    );
    
    return {
        dependencies   => $all_dependencies,
        file_io        => $all_file_io,
        db_operations  => $all_db_ops,
    };
}

sub _resolve_recursive {
    my ($self, $entry_file, $current_file, $depth, $deps, $file_ios, $db_ops, $call_type) = @_;
    $call_type //= 'execute';  # default: execute
    
    # Check max depth
    if ($depth >= $self->{max_depth}) {
        $self->{logger}->warn("最大深度到達: $current_file (深度: $depth)") if $self->{logger};
        return;
    }
    
    # Check if already analyzed (prevent infinite loops)
    if (exists $self->{analyzed_files}{$current_file}) {
        return;
    }
    
    $self->{analyzed_files}{$current_file} = 1;
    
    # Check if file exists
    unless (-f $current_file) {
        $self->{logger}->warn("ファイルが見つかりません: $current_file") if $self->{logger};
        return;
    }
    
    # Clear script-defined variables only for entry point and execute calls
    # source calls inherit variables from the caller scope
    if ($self->{var_resolver} && $call_type ne 'source') {
        $self->{var_resolver}->clear_script_variables();
    }
    
    # Detect language
    my $lang = $self->{language_detector}->detect($current_file, $self->{encoding});
    unless ($lang) {
        $self->{logger}->warn("言語判定失敗: $current_file") if $self->{logger};
        return;
    }
    
    # Create appropriate analyzer
    my $analyzer = $self->_create_analyzer($lang, $current_file);
    unless ($analyzer) {
        $self->{logger}->warn("アナライザー作成失敗: $current_file (言語: $lang)") if $self->{logger};
        return;
    }
    
    my $current_basename = basename($current_file);
    my $current_dir = dirname($current_file);
    
    # 2-pass analysis for shell scripts to properly resolve sourced variables
    if ($lang eq 'sh' || $lang eq 'csh') {
        # Pass 1: Extract variables and process source calls first
        eval {
            my @source_calls = $analyzer->analyze_pass1();
            
            # Process source calls recursively BEFORE pass 2
            # This ensures variables from sourced files are available
            foreach my $call (@source_calls) {
                my $called_name = $call->{name};
                my $line_num = $call->{line};
                
                my $resolved_path = $self->{file_mapper}->resolve($called_name, $current_dir, $self->{logger});
                
                if ($resolved_path && !exists $self->{analyzed_files}{$resolved_path}) {
                    # Detect language of called file
                    my $called_lang = $self->{language_detector}->detect($resolved_path, $self->{encoding});
                    
                    push @$deps, {
                        entry_point => $entry_file,
                        caller      => $current_basename,
                        callee      => basename($resolved_path),
                        language    => $called_lang // 'unknown',
                        depth       => $depth,
                        caller_path => $current_file,
                        callee_path => $resolved_path,
                        line_number => $line_num,
                        call_type   => 'source',
                    };
                    
                    # Recursively analyze sourced file (pass call_type=source to preserve variables)
                    $self->_resolve_recursive(
                        $entry_file,
                        $resolved_path,
                        $depth + 1,
                        $deps,
                        $file_ios,
                        $db_ops,
                        'source'
                    );
                } elsif (!$resolved_path) {
                    $self->{logger}->warn("source先未解決: $called_name (行: $line_num, ファイル: $current_file)") if $self->{logger};
                }
            }
        };
        if ($@) {
            $self->{logger}->warn("Pass1解析エラー: $current_file - $@") if $self->{logger};
            return;
        }
        
        # Pass 2: Full analysis with all sourced variables now available
        eval {
            $analyzer->analyze_pass2();
        };
        if ($@) {
            $self->{logger}->warn("Pass2解析エラー: $current_file - $@") if $self->{logger};
            return;
        }
    } else {
        # Non-shell files: use single-pass analysis
        eval {
            $analyzer->analyze();
        };
        if ($@) {
            $self->{logger}->warn("解析エラー: $current_file - $@") if $self->{logger};
            return;
        }
    }
    
    # Process calls (for pass 2 results, or single-pass for non-shell)
    foreach my $call ($analyzer->get_calls()) {
        my $called_name = $call->{name};
        my $line_num = $call->{line};
        my $this_call_type = $call->{type} // 'execute';
        
        # Skip source calls for shell scripts (already processed in pass 1)
        next if ($lang eq 'sh' || $lang eq 'csh') && $this_call_type eq 'source';
        
        # Resolve the called file
        my $resolved_path = $self->{file_mapper}->resolve($called_name, $current_dir, $self->{logger});
        
        if ($resolved_path) {
            # Detect language of called file
            my $called_lang = $self->{language_detector}->detect($resolved_path, $self->{encoding});
            
            push @$deps, {
                entry_point => $entry_file,
                caller      => $current_basename,
                callee      => basename($resolved_path),
                language    => $called_lang // 'unknown',
                depth       => $depth,
                caller_path => $current_file,
                callee_path => $resolved_path,
                line_number => $line_num,
                call_type   => $this_call_type,
            };
            
            # Recursive analysis
            $self->_resolve_recursive(
                $entry_file,
                $resolved_path,
                $depth + 1,
                $deps,
                $file_ios,
                $db_ops,
                $this_call_type
            );
        } else {
            $self->{logger}->warn("呼び出し先未解決: $called_name (行: $line_num, ファイル: $current_file)") if $self->{logger};
        }
    }
    
    # Process file I/O
    foreach my $io ($analyzer->get_file_io()) {
        push @$file_ios, {
            file     => $current_file,
            type     => $io->{type},
            target   => $io->{target},
            line     => $io->{line},
        };
    }
    
    # Process DB operations
    foreach my $db_op ($analyzer->get_db_operations()) {
        push @$db_ops, {
            file      => $current_file,
            operation => $db_op->{operation},
            table     => $db_op->{table},
            line      => $db_op->{line},
        };
    }
}

sub _create_analyzer {
    my ($self, $lang, $filepath) = @_;
    
    my %analyzer_map = (
        sh     => 'Analyzer::Sh',
        csh    => 'Analyzer::Csh',
        cobol  => 'Analyzer::Cobol',
        plsql  => 'Analyzer::Plsql',
    );
    
    my $analyzer_class = $analyzer_map{$lang};
    return undef unless $analyzer_class;
    
    return $analyzer_class->new(
        filepath     => $filepath,
        encoding     => $self->{encoding},
        logger       => $self->{logger},
        file_mapper  => $self->{file_mapper},
        var_resolver => $self->{var_resolver},
    );
}

1;
