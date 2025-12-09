package FileMapper;
use strict;
use warnings;
use File::Find;
use File::Basename;
use File::Spec;

sub new {
    my $class = shift;
    my $self = {
        name_to_paths => {},  # basename => [full_paths]
    };
    bless $self, $class;
    return $self;
}

sub scan_directory {
    my ($self, $dir) = @_;
    return unless -d $dir;
    
    find(sub {
        return unless -f $_;
        my $fullpath = $File::Find::name;
        $self->add_file($fullpath);
    }, $dir);
}

sub add_file {
    my ($self, $filepath) = @_;
    my $basename = basename($filepath);
    
    push @{$self->{name_to_paths}{$basename}}, $filepath;
}

sub resolve {
    my ($self, $name, $current_dir) = @_;
    
    # If already an absolute path that exists, return it
    return $name if File::Spec->file_name_is_absolute($name) && -f $name;
    
    # If relative path from current directory
    if ($current_dir && !File::Spec->file_name_is_absolute($name)) {
        my $full_path = File::Spec->catfile($current_dir, $name);
        return $full_path if -f $full_path;
    }
    
    # Strip directory part if present and lookup by basename
    my $basename = basename($name);
    
    # Remove common extensions to search for base name
    my $name_without_ext = $basename;
    $name_without_ext =~ s/\.(sh|csh|bash|tcsh|cbl|cob|pls|sql)$//i;
    
    # Try exact basename match
    if (exists $self->{name_to_paths}{$basename}) {
        return $self->{name_to_paths}{$basename}[0];
    }
    
    # Try without extension
    if (exists $self->{name_to_paths}{$name_without_ext}) {
        return $self->{name_to_paths}{$name_without_ext}[0];
    }
    
    # Try with common extensions
    foreach my $ext ('', '.sh', '.csh', '.cbl', '.pls', '.sql') {
        my $try_name = $name_without_ext . $ext;
        if (exists $self->{name_to_paths}{$try_name}) {
            return $self->{name_to_paths}{$try_name}[0];
        }
    }
    
    return undef;
}

sub get_all_paths {
    my ($self, $name) = @_;
    my $basename = basename($name);
    return @{$self->{name_to_paths}{$basename} // []};
}

1;
