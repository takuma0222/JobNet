package Analyzer::Sh;
use strict;
use warnings;
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
    foreach my $line (@lines) {
        $line_num++;
        
        # Remove comments
        $line =~ s/#.*$//;
        
        # Detect script calls
        $self->detect_calls($line, $line_num);
        
        # Detect file I/O
        $self->detect_file_io($line, $line_num);
        
        # Detect DB operations (sqlplus)
        $self->detect_db_operations($line, $line_num);
    }
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
    if ($line =~ /sqlplus/i) {
        # Just note that sqlplus is used
        if ($self->{logger}) {
            $self->{logger}->info("sqlplus実行検出: (行: $line_num)");
        }
    }
}

1;
