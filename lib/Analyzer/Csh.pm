package Analyzer::Csh;
use strict;
use warnings;
use utf8;
use parent 'Analyzer::Base';

sub analyze {
    my ($self) = @_;
    my @lines = $self->read_file();
    
    # Read entire file content for variable extraction
    my $content = join('', @lines);
    
    # Extract csh-style variable definitions if VariableResolver is available
    if ($self->{var_resolver}) {
        $self->extract_csh_variables($content);
    }
    
    my $line_num = 0;
    my $heredoc_end = undef;  # Track here-document terminator
    
    foreach my $line (@lines) {
        $line_num++;
        
        # Skip lines inside here-document
        if (defined $heredoc_end) {
            if ($line =~ /^\s*\Q$heredoc_end\E\s*$/) {
                $heredoc_end = undef;
            }
            next;
        }
        
        # Detect here-document start
        if ($line =~ /<<\s*['"]?([A-Za-z_][A-Za-z0-9_]*)['"]?/) {
            $heredoc_end = $1;
        }
        
        # Remove comments (but not inside quotes)
        my $code_line = $self->_remove_comments($line);
        
        # Detect script calls
        $self->detect_calls($code_line, $line_num);
        
        # Detect file I/O
        $self->detect_file_io($code_line, $line_num);
    }
}

# Pass 1 only: Extract variables and source calls for 2-pass analysis
sub analyze_pass1 {
    my ($self) = @_;
    
    my @lines = $self->read_file();
    my $content = join('', @lines);
    
    # Extract csh-style variable definitions
    if ($self->{var_resolver}) {
        $self->extract_csh_variables($content);
    }
    
    my $line_num = 0;
    my $heredoc_end = undef;
    
    foreach my $line (@lines) {
        $line_num++;
        
        if (defined $heredoc_end) {
            if ($line =~ /^\s*\Q$heredoc_end\E\s*$/) {
                $heredoc_end = undef;
            }
            next;
        }
        
        if ($line =~ /<<\s*['"]?([A-Za-z_][A-Za-z0-9_]*)['"]?/) {
            $heredoc_end = $1;
        }
        
        my $code_line = $self->_remove_comments($line);
        
        # Only detect source calls in pass 1
        $self->detect_source_calls($code_line, $line_num);
    }
    
    return @{$self->{calls}};
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
        
        if (defined $heredoc_end) {
            if ($line =~ /^\s*\Q$heredoc_end\E\s*$/) {
                $heredoc_end = undef;
            }
            next;
        }
        
        if ($line =~ /<<\s*['"]?([A-Za-z_][A-Za-z0-9_]*)['"]?/) {
            $heredoc_end = $1;
        }
        
        my $code_line = $self->_remove_comments($line);
        
        # Full analysis with variables available
        $self->detect_calls($code_line, $line_num);
        $self->detect_file_io($code_line, $line_num);
    }
}

# Detect only source calls (for pass 1)
sub detect_source_calls {
    my ($self, $line, $line_num) = @_;
    
    # source command: source file.csh or source file (without extension)
    if ($line =~ /source\s+([^\s;|&]+)/) {
        my $script = $1;
        return if $script =~ /^-/;  # Skip options
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
        
        if ($prev_char eq '\\') {
            $result .= $char;
            $i++;
            next;
        }
        
        if ($char eq "'" && !$in_double_quote) {
            $in_single_quote = !$in_single_quote;
            $result .= $char;
        } elsif ($char eq '"' && !$in_single_quote) {
            $in_double_quote = !$in_double_quote;
            $result .= $char;
        } elsif ($char eq '#' && !$in_single_quote && !$in_double_quote) {
            last;
        } else {
            $result .= $char;
        }
        $i++;
    }
    
    return $result;
}

sub extract_csh_variables {
    my ($self, $content) = @_;
    
    # csh uses: set VAR=value or setenv VAR value
    while ($content =~ /^\s*set\s+([A-Za-z_][A-Za-z0-9_]*)=(.+?)(?:\s*[#;\n]|$)/gm) {
        my ($name, $value) = ($1, $2);
        $value =~ s/\s+$//;
        $value =~ s/^["']|["']$//g;
        $self->{var_resolver}->{variables}{$name} = $value;
    }
    
    while ($content =~ /^\s*setenv\s+([A-Za-z_][A-Za-z0-9_]*)\s+(.+?)(?:\s*[#;\n]|$)/gm) {
        my ($name, $value) = ($1, $2);
        $value =~ s/\s+$//;
        $value =~ s/^["']|["']$//g;
        $self->{var_resolver}->{variables}{$name} = $value;
    }
}

sub detect_calls {
    my ($self, $line, $line_num) = @_;
    
    # source command: source file (extension-independent)
    if ($line =~ /source\s+([^\s;|&]+)/) {
        my $script = $1;
        # Skip options
        unless ($script =~ /^-/) {
            $script = $self->{var_resolver}->expand_path($script) if $self->{var_resolver};
            $self->add_call($script, $line_num, 'source');
        }
    }
    
    # Absolute path execution (extension-independent)
    # Match: /path/to/script, /A/B/AAAA, /opt/batch/job.jcl, etc.
    unless ($line =~ /^\s*(?:echo|print|printf|cat)\s/ || $line =~ /^\s*(?:set|setenv)\s/) {
        while ($line =~ m{(?:^|\s|&&|\|\||;)\s*(/[A-Za-z0-9/_\-\$\{\}\.]+)}g) {
            my $cmd = $1;
            # Skip system directories
            next if $cmd =~ m{^/(?:bin|usr|sbin|lib|etc|dev|proc|sys)/};
            # Skip if it looks like a file path being redirected to
            next if $line =~ /[>]\s*\Q$cmd\E/;
            
            $cmd = $self->{var_resolver}->expand_path($cmd) if $self->{var_resolver};
            $self->add_call($cmd, $line_num, 'execute');
        }
    }
}

sub detect_file_io {
    my ($self, $line, $line_num) = @_;
    
    # Output redirection: > file, >> file, >! file, >>! file (csh force overwrite)
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
    
    # Input redirection: < file
    if ($line =~ /<\s*([^\s;|&]+)/) {
        my $file = $1;
        $file = $self->{var_resolver}->expand_path($file) if $self->{var_resolver};
        $self->add_file_io('INPUT', $file, $line_num);
    }
    
    # cat command: cat file
    if ($line =~ /\bcat\s+([^\s;|&>]+)/) {
        my $file = $1;
        unless ($file eq '-') {
            $file = $self->{var_resolver}->expand_path($file) if $self->{var_resolver};
            $self->add_file_io('INPUT', $file, $line_num);
        }
    }
}

1;
