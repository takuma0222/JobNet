package Analyzer::Sh;
use strict;
use warnings;
use utf8;
use parent 'Analyzer::Base';

sub analyze {
    my ($self) = @_;
    
    # 2-pass analysis for proper variable resolution from sourced files
    # Pass 1: Extract variables and detect source calls only
    # Pass 2: Full analysis with all variables available
    
    my @lines = $self->read_file();
    
    # Read entire file content for variable extraction
    my $content = join('', @lines);
    
    # Extract variable definitions if VariableResolver is available
    if ($self->{var_resolver}) {
        $self->{var_resolver}->extract_variables($content);
    }
    
    my $line_num = 0;
    my $heredoc_end = undef;  # Track here-document terminator
    
    foreach my $line (@lines) {
        $line_num++;
        
        # Skip lines inside here-document
        if (defined $heredoc_end) {
            if ($line =~ /^\s*\Q$heredoc_end\E\s*$/) {
                $heredoc_end = undef;  # End of here-document
            }
            next;
        }
        
        # Detect here-document start: <<TAG, <<'TAG', <<"TAG", <<-TAG
        if ($line =~ /<<-?\s*['"]?([A-Za-z_][A-Za-z0-9_]*)['"]?/) {
            $heredoc_end = $1;
        }
        
        # Remove comments (but not inside quotes)
        my $code_line = $self->_remove_comments($line);
        
        # Detect script calls
        $self->detect_calls($code_line, $line_num);
        
        # Detect file I/O
        $self->detect_file_io($code_line, $line_num);
        
        # Detect DB operations (sqlplus)
        $self->detect_db_operations($code_line, $line_num);
    }
}

# Pass 1 only: Extract variables and source calls for 2-pass analysis
# This is called by DependencyResolver to collect variables from sourced files first
sub analyze_pass1 {
    my ($self) = @_;
    
    my @lines = $self->read_file();
    my $content = join('', @lines);
    
    # Extract variable definitions
    if ($self->{var_resolver}) {
        $self->{var_resolver}->extract_variables($content);
    }
    
    my $line_num = 0;
    my $heredoc_end = undef;
    
    foreach my $line (@lines) {
        $line_num++;
        
        # Skip lines inside here-document
        if (defined $heredoc_end) {
            if ($line =~ /^\s*\Q$heredoc_end\E\s*$/) {
                $heredoc_end = undef;
            }
            next;
        }
        
        if ($line =~ /<<-?\s*['"]?([A-Za-z_][A-Za-z0-9_]*)['"]?/) {
            $heredoc_end = $1;
        }
        
        my $code_line = $self->_remove_comments($line);
        
        # Only detect source calls in pass 1
        $self->detect_source_calls($code_line, $line_num);
    }
    
    return @{$self->{calls}};  # Return source calls for processing
}

# Pass 2: Full analysis with all variables from sourced files available
sub analyze_pass2 {
    my ($self) = @_;
    
    # Clear previous analysis results
    $self->{calls} = [];
    $self->{file_io} = [];
    $self->{db_operations} = [];
    
    my @lines = $self->read_file();
    
    my $line_num = 0;
    my $heredoc_end = undef;
    
    foreach my $line (@lines) {
        $line_num++;
        
        # Skip lines inside here-document
        if (defined $heredoc_end) {
            if ($line =~ /^\s*\Q$heredoc_end\E\s*$/) {
                $heredoc_end = undef;
            }
            next;
        }
        
        if ($line =~ /<<-?\s*['"]?([A-Za-z_][A-Za-z0-9_]*)['"]?/) {
            $heredoc_end = $1;
        }
        
        my $code_line = $self->_remove_comments($line);
        
        # Full analysis with variables available
        $self->detect_calls($code_line, $line_num);
        $self->detect_file_io($code_line, $line_num);
        $self->detect_db_operations($code_line, $line_num);
    }
}

# Detect only source calls (for pass 1)
sub detect_source_calls {
    my ($self, $line, $line_num) = @_;
    
    # source command: source file.sh or . file.sh
    # Also match files without extension for csh files
    if ($line =~ /(?:source|\.)\s+([^\s;|&]+)/) {
        my $script = $1;
        # Filter out obvious non-script arguments
        return if $script =~ /^-/;  # Skip options like -e
        $script = $self->{var_resolver}->expand_path($script) if $self->{var_resolver};
        $self->add_call($script, $line_num, 'source');
    }
}

# Remove comments while respecting quoted strings
sub _remove_comments {
    my ($self, $line) = @_;
    
    my $result = '';
    my $in_single_quote = 0;
    my $in_double_quote = 0;
    my $i = 0;
    my $len = length($line);
    
    while ($i < $len) {
        my $char = substr($line, $i, 1);
        my $prev_char = $i > 0 ? substr($line, $i - 1, 1) : '';
        
        # Handle escape sequences
        if ($prev_char eq '\\') {
            $result .= $char;
            $i++;
            next;
        }
        
        # Toggle quote states
        if ($char eq "'" && !$in_double_quote) {
            $in_single_quote = !$in_single_quote;
            $result .= $char;
        } elsif ($char eq '"' && !$in_single_quote) {
            $in_double_quote = !$in_double_quote;
            $result .= $char;
        } elsif ($char eq '#' && !$in_single_quote && !$in_double_quote) {
            # Comment starts here, ignore rest of line
            last;
        } else {
            $result .= $char;
        }
        $i++;
    }
    
    return $result;
}

sub detect_calls {
    my ($self, $line, $line_num) = @_;
    
    # source command: source file or . file (extension-independent)
    if ($line =~ /(?:source|\.)\s+([^\s;|&]+)/) {
        my $script = $1;
        # Skip options like -e
        unless ($script =~ /^-/) {
            $script = $self->{var_resolver}->expand_path($script) if $self->{var_resolver};
            $self->add_call($script, $line_num, 'source');
        }
    }
    
    # Absolute path execution (extension-independent)
    # Match: /path/to/script, /A/B/AAAA, ${VAR}/path, $VAR/path, etc.
    my $check_line = $line;
    
    # Pattern 1: Absolute path starting with /
    while ($check_line =~ m{(?:^|\s|&&|\|\||;)\s*(/[A-Za-z0-9/_\-\.\$\{\}]+)}g) {
        my $cmd = $1;
        # Skip system directories
        next if $cmd =~ m{^/(?:bin|usr|sbin|lib|etc|dev|proc|sys)/};
        # Skip if it looks like a file path being redirected to
        next if $line =~ /[>]\s*\Q$cmd\E/;
        # Skip if cmd is an argument to echo/print (not after && or ||)
        # e.g., "echo /path" should skip, but "echo x && /path" should not
        next if $line =~ /^\s*(?:echo|print|printf)\s+[^&|;]*\Q$cmd\E/ && 
                $line !~ /(?:&&|\|\||;)\s*\Q$cmd\E/;
        
        $cmd = $self->{var_resolver}->expand_path($cmd) if $self->{var_resolver};
        $self->add_call($cmd, $line_num, 'execute');
    }
    
    # Pattern 2: Variable-based absolute path (${VAR}/path or $VAR/path)
    while ($check_line =~ m{(?:^|\s|&&|\|\||;)\s*(\$\{?[A-Za-z_][A-Za-z0-9_]*\}?/[A-Za-z0-9/_\-\.\$\{\}]*)}g) {
        my $cmd = $1;
        # Skip if it looks like assignment
        next if $line =~ /^\s*\w+=/;
        # Skip if it looks like a file path being redirected to
        next if $line =~ /[>]\s*\Q$cmd\E/;
        # Skip if cmd is an argument to echo/print (not after && or ||)
        next if $line =~ /^\s*(?:echo|print|printf)\s+[^&|;]*\Q$cmd\E/ && 
                $line !~ /(?:&&|\|\||;)\s*\Q$cmd\E/;
        
        $cmd = $self->{var_resolver}->expand_path($cmd) if $self->{var_resolver};
        $self->add_call($cmd, $line_num, 'execute');
    }
    
    # Pattern 3: Relative path starting with ./ or ../
    while ($check_line =~ m{(?:^|\s|&&|\|\||;)\s*(\.\.?/[A-Za-z0-9/_\-\.\$\{\}]+)}g) {
        my $cmd = $1;
        # Skip if it looks like a file path being redirected to
        next if $line =~ /[>]\s*\Q$cmd\E/;
        # Skip if cmd is an argument to echo/print (not after && or ||)
        next if $line =~ /^\s*(?:echo|print|printf)\s+[^&|;]*\Q$cmd\E/ && 
                $line !~ /(?:&&|\|\||;)\s*\Q$cmd\E/;
        
        $cmd = $self->{var_resolver}->expand_path($cmd) if $self->{var_resolver};
        $self->add_call($cmd, $line_num, 'execute');
    }
    
    # Pattern 4: Variable-only execution (${VAR} or $VAR at start of command)
    while ($check_line =~ m{(?:^|\s|&&|\|\||;)\s*(\$\{?[A-Za-z_][A-Za-z0-9_]*\}?)(?:\s|$|;|&|\|)}g) {
        my $cmd = $1;
        # Skip if it looks like assignment
        next if $line =~ /^\s*\w+=/;
        # Skip if cmd is an argument to echo/print (not after && or ||)
        next if $line =~ /^\s*(?:echo|print|printf)\s+[^&|;]*\Q$cmd\E/ && 
                $line !~ /(?:&&|\|\||;)\s*\Q$cmd\E/;
        
        $cmd = $self->{var_resolver}->expand_path($cmd) if $self->{var_resolver};
        # Only add if it looks like a path after expansion (contains / or is non-empty)
        if ($cmd =~ m{/} || $cmd !~ /^\$/) {
            $self->add_call($cmd, $line_num, 'execute');
        }
    }
}

sub detect_file_io {
    my ($self, $line, $line_num) = @_;
    
    # Output redirection: > file or >> file (also handles >! and >>! for csh)
    # Pattern: >! or >>! followed by file, or > or >> followed by file
    if ($line =~ /(?:>>?!?)\s*([^\s;|&]+)/) {
        my $file = $1;
        # Handle >! pattern: strip leading ! if present
        $file =~ s/^!//;
        # Only add if file is valid (not empty and not just a number)
        unless ($file eq '' || $file =~ /^\d+$/) {
            $file = $self->{var_resolver}->expand_path($file) if $self->{var_resolver};
            $self->add_file_io('OUTPUT', $file, $line_num);
        }
    }
    
    # Input redirection: < file (but not << for here-document)
    if ($line =~ /(?<!<)<(?!<)\s*([^\s;|&]+)/) {
        my $file = $1;
        $file = $self->{var_resolver}->expand_path($file) if $self->{var_resolver};
        $self->add_file_io('INPUT', $file, $line_num);
    }
    
    # cat command: cat file
    if ($line =~ /\bcat\s+([^\s;|&>]+)/) {
        my $file = $1;
        unless ($file eq '-' || $file =~ /^[<>]/) {
            $file = $self->{var_resolver}->expand_path($file) if $self->{var_resolver};
            $self->add_file_io('INPUT', $file, $line_num);
        }
    }
    
    # cp command: cp source dest
    if ($line =~ /\bcp\s+([^\s;|&]+)\s+([^\s;|&]+)/) {
        my ($src, $dst) = ($1, $2);
        $src = $self->{var_resolver}->expand_path($src) if $self->{var_resolver};
        $dst = $self->{var_resolver}->expand_path($dst) if $self->{var_resolver};
        $self->add_file_io('INPUT', $src, $line_num);
        $self->add_file_io('OUTPUT', $dst, $line_num);
    }
    
    # mv command: mv source dest
    if ($line =~ /\bmv\s+([^\s;|&]+)\s+([^\s;|&]+)/) {
        my ($src, $dst) = ($1, $2);
        $src = $self->{var_resolver}->expand_path($src) if $self->{var_resolver};
        $dst = $self->{var_resolver}->expand_path($dst) if $self->{var_resolver};
        $self->add_file_io('INPUT', $src, $line_num);
        $self->add_file_io('OUTPUT', $dst, $line_num);
    }
}

sub detect_db_operations {
    my ($self, $line, $line_num) = @_;
    
    # Direct SQL in the line
    if ($line =~ /(?:INSERT|UPDATE|DELETE|SELECT)\s+/i) {
        if ($line =~ /INSERT\s+INTO\s+(\w+)/i) {
            $self->add_db_operation('INSERT', $1, $line_num);
        } elsif ($line =~ /UPDATE\s+(\w+)/i) {
            $self->add_db_operation('UPDATE', $1, $line_num);
        } elsif ($line =~ /DELETE\s+FROM\s+(\w+)/i) {
            $self->add_db_operation('DELETE', $1, $line_num);
        } elsif ($line =~ /SELECT\s+.*?\s+FROM\s+(\w+)/i) {
            $self->add_db_operation('SELECT', $1, $line_num);
        }
    }
    
    # sqlplus commands (basic detection)
    if ($line =~ /sqlplus\s+(?:[^\s@]+\/[^\s@]+@[^\s]+)?\s*@?([^\s]+)/i) {
        my $script = $1;
        $self->add_db_operation('SQLPLUS', $script, $line_num);
        if ($self->{logger}) {
            $self->{logger}->info("sqlplus実行検出: $script (行: $line_num)");
        }
    }
}

1;
