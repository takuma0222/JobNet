package Analyzer::Csh;
use strict;
use warnings;
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
    foreach my $line (@lines) {
        $line_num++;
        
        # Remove comments
        $line =~ s/#.*$//;
        
        # Detect script calls
        $self->detect_calls($line, $line_num);
        
        # Detect file I/O
        $self->detect_file_io($line, $line_num);
    }
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
    
    # source command: source file.csh
    if ($line =~ /source\s+([^\s;|&]+\.(?:csh|tcsh))/) {
        my $script = $1;
        $script = $self->{var_resolver}->expand_path($script) if $self->{var_resolver};
        $self->add_call($script, $line_num);
    }
    
    # Direct script execution: /path/to/script.csh or ./script.csh
    if ($line =~ m{([/.\w\$\{\}]+\.(?:csh|tcsh))}) {
        my $script = $1;
        unless ($line =~ /echo|print/) {
            $script = $self->{var_resolver}->expand_path($script) if $self->{var_resolver};
            $self->add_call($script, $line_num);
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
        unless ($file eq '-') {
            $file = $self->{var_resolver}->expand_path($file) if $self->{var_resolver};
            $self->add_file_io('INPUT', $file, $line_num);
        }
    }
}

1;
