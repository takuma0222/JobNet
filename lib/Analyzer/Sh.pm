package Analyzer::Sh;
use strict;
use warnings;
use utf8;
use parent 'Analyzer::Base';

sub analyze {
    my ($self) = @_;
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
    
    # source command: source file.sh or . file.sh
    if ($line =~ /(?:source|\.)\s+([^\s;|&]+\.(?:sh|bash|csh))/) {
        my $script = $1;
        $script = $self->{var_resolver}->expand_path($script) if $self->{var_resolver};
        $self->add_call($script, $line_num);
    }
    
    # Direct script execution: /path/to/script.sh or ./script.sh
    if ($line =~ m{([/\.\w\-\$\{\}]+\.(?:sh|bash|csh))}) {
        my $script = $1;
        # Avoid false positives from strings in echo, etc.
        unless ($line =~ /echo|print|cat.*<</) {
            $script = $self->{var_resolver}->expand_path($script) if $self->{var_resolver};
            $self->add_call($script, $line_num);
        }
    }
    
    # Executable without extension (common pattern)
    if ($line =~ m{^\s*([/\w\-\$\{\}]+/[\w\-]+)\s*$} || $line =~ m{\s+([/\w\-\$\{\}]+/[\w\-]+)\s*[;&|]}) {
        my $cmd = $1;
        # Check if it looks like a script path
        if ($cmd =~ m{/} && $cmd !~ /^\/(?:bin|usr|etc|var|tmp)/) {
            $cmd = $self->{var_resolver}->expand_path($cmd) if $self->{var_resolver};
            $self->add_call($cmd, $line_num);
        }
    }
}

sub detect_file_io {
    my ($self, $line, $line_num) = @_;
    
    # Output redirection: > file or >> file
    if ($line =~ /(?:>>?)\s*([^\s;|&]+)/) {
        my $file = $1;
        $file = $self->{var_resolver}->expand_path($file) if $self->{var_resolver};
        $self->add_file_io('OUTPUT', $file, $line_num);
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
