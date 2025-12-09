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
    # Pattern 5: export VAR=value (bash export)
    # Pattern 6: declare VAR=value (bash declare)
    
    # Handle: export VAR=value or export VAR="value"
    while ($content =~ /^\s*(?:export|declare(?:\s+-[a-z]+)?)\s+([A-Za-z_][A-Za-z0-9_]*)=(.+?)(?:\s*[#;\n]|$)/gm) {
        my ($name, $value) = ($1, $2);
        $value =~ s/\s+$//;
        $value =~ s/^["']|["']$//g;
        $self->{variables}{$name} = $value;
    }
    
    # Handle: VAR=value (standard assignment)
    while ($content =~ /^\s*([A-Za-z_][A-Za-z0-9_]*)=(.+?)(?:\s*[#;\n]|$)/gm) {
        my ($name, $value) = ($1, $2);
        
        # Skip if already set (export takes precedence in order of appearance)
        next if exists $self->{variables}{$name};
        
        # Remove trailing whitespace
        $value =~ s/\s+$//;
        
        # Remove quotes (double or single)
        $value =~ s/^["']|["']$//g;
        
        # Store the variable
        $self->{variables}{$name} = $value;
    }
    
    # Second pass: expand variable references in stored values
    $self->_expand_stored_variables();
}

# Expand variable references within stored variable values
sub _expand_stored_variables {
    my ($self) = @_;
    my $max_iterations = 10;
    my %seen;  # Track expansion history to detect circular references
    
    for (my $i = 0; $i < $max_iterations; $i++) {
        my $changed = 0;
        foreach my $name (keys %{$self->{variables}}) {
            my $value = $self->{variables}{$name};
            
            # Skip if no variable references
            next unless $value =~ /\$/;
            
            # Detect circular reference
            my $key = "$name:$value";
            if ($seen{$key}++) {
                if ($self->{logger}) {
                    $self->{logger}->warn("循環参照を検出: $name = $value");
                }
                next;
            }
            
            my $new_value = $self->_expand_path_internal($value, {$name => 1});
            if ($new_value ne $value) {
                $self->{variables}{$name} = $new_value;
                $changed = 1;
            }
        }
        last unless $changed;
    }
}

# Internal expand_path that tracks visited variables to prevent infinite loops
sub _expand_path_internal {
    my ($self, $path, $visiting) = @_;
    $visiting //= {};
    
    return $path unless defined $path;
    
    my $max_iterations = 10;
    my $iteration = 0;
    
    while ($iteration < $max_iterations) {
        my $changed = 0;
        
        # Expand ${VAR} pattern
        $path =~ s/\$\{([A-Za-z_][A-Za-z0-9_]*)\}/
            $visiting->{$1} ? "\${$1}" : $self->resolve_variable($1)
        /ge and $changed = 1;
        
        # Expand $VAR pattern
        $path =~ s/\$([A-Za-z_][A-Za-z0-9_]*)(?=\/|:|$|\s|\.|\-|_(?![A-Za-z0-9]))/
            $visiting->{$1} ? "\$$1" : $self->resolve_variable($1)
        /ge and $changed = 1;
        
        # Handle $VAR at end of string
        $path =~ s/\$([A-Za-z_][A-Za-z0-9_]*)$/
            $visiting->{$1} ? "\$$1" : $self->resolve_variable($1)
        /e and $changed = 1;
        
        last unless $changed;
        $iteration++;
    }
    
    return $path;
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
        # Match $VAR followed by: /, :, end of string, whitespace, or common delimiters
        # Also handle $VAR at end of string or before non-alphanumeric chars
        if ($path =~ s/\$([A-Za-z_][A-Za-z0-9_]*)(?=\/|:|$|\s|\.|\-|_(?![A-Za-z0-9]))/$self->resolve_variable($1)/ge) {
            $changed = 1;
        }
        
        # Handle $VAR at end of string (no lookahead needed)
        if ($path =~ s/\$([A-Za-z_][A-Za-z0-9_]*)$/$self->resolve_variable($1)/e) {
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
