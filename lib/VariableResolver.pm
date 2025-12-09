package VariableResolver;
use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    my $self = {
        variables => {},                    # Variables defined in scripts
        env_vars  => \%ENV,                 # Environment variables
        cli_vars  => $args{cli_vars} || {}, # CLI-specified variables (--env)
        logger    => $args{logger},         # Logger instance
    };
    return bless $self, $class;
}

# Extract variable definitions from script content
sub extract_variables {
    my ($self, $content) = @_;
    
    # Pattern 1: VAR=value (without quotes)
    # Pattern 2: VAR="value" (double quotes)
    # Pattern 3: VAR='value' (single quotes)
    # Pattern 4: VAR=${OTHER}/path (variable reference in value)
    while ($content =~ /^\s*([A-Za-z_][A-Za-z0-9_]*)=(.+?)(?:\s*[#;\n]|$)/gm) {
        my ($name, $value) = ($1, $2);
        
        # Remove trailing whitespace
        $value =~ s/\s+$//;
        
        # Remove quotes (double or single)
        $value =~ s/^["']|["']$//g;
        
        # Store the variable
        $self->{variables}{$name} = $value;
    }
}

# Expand variables in a path
sub expand_path {
    my ($self, $path) = @_;
    
    return $path unless defined $path;
    
    my $original_path = $path;
    my $max_iterations = 10;  # Prevent infinite loops
    my $iteration = 0;
    
    while ($iteration < $max_iterations) {
        my $changed = 0;
        
        # Expand ${VAR} pattern
        if ($path =~ s/\$\{([A-Za-z_][A-Za-z0-9_]*)\}/$self->resolve_variable($1)/ge) {
            $changed = 1;
        }
        
        # Expand $VAR pattern (but not $$ or $digit)
        # Use word boundary or specific delimiters to avoid matching $VAR in middle of text
        if ($path =~ s/\$([A-Za-z_][A-Za-z0-9_]*)(?=\/|:|$|\s)/$self->resolve_variable($1)/ge) {
            $changed = 1;
        }
        
        last unless $changed;
        $iteration++;
    }
    
    # Log if variable couldn't be fully resolved
    if ($path =~ /\$/) {
        if ($self->{logger}) {
            $self->{logger}->warn("未解決の変数が含まれています: $original_path -> $path");
        }
    }
    
    return $path;
}

# Resolve a single variable name
# Priority: CLI > Script > Environment
sub resolve_variable {
    my ($self, $name) = @_;
    
    # Priority 1: CLI-specified variables (--env)
    if (exists $self->{cli_vars}{$name}) {
        return $self->{cli_vars}{$name};
    }
    
    # Priority 2: Script-defined variables
    if (exists $self->{variables}{$name}) {
        return $self->{variables}{$name};
    }
    
    # Priority 3: Environment variables
    if (exists $self->{env_vars}{$name}) {
        return $self->{env_vars}{$name};
    }
    
    # Unresolved - return as-is with braces
    return "\${$name}";
}

# Get all variables (for debugging)
sub get_all_variables {
    my ($self) = @_;
    return {
        cli_vars    => $self->{cli_vars},
        variables   => $self->{variables},
        env_vars    => { map { $_ => $ENV{$_} } keys %ENV },
    };
}

# Clear script-defined variables (useful when analyzing a new file)
sub clear_script_variables {
    my ($self) = @_;
    $self->{variables} = {};
}

1;
