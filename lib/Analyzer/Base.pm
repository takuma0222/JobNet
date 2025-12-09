package Analyzer::Base;
use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    my $self = {
        filepath      => $args{filepath},
        encoding      => $args{encoding} // 'utf-8',
        logger        => $args{logger},
        file_mapper   => $args{file_mapper},
        var_resolver  => $args{var_resolver},
        calls         => [],      # List of called programs/scripts
        file_io       => [],      # List of file I/O operations
        db_operations => [],      # List of database operations
    };
    bless $self, $class;
    return $self;
}

sub analyze {
    my ($self) = @_;
    # Override in subclasses
    die "analyze() must be implemented in subclass";
}

sub read_file {
    my ($self) = @_;
    my $filepath = $self->{filepath};
    
    open my $fh, "<:encoding($self->{encoding})", $filepath
        or die "Cannot open file: $filepath\n";
    
    my @lines;
    while (my $line = <$fh>) {
        push @lines, $line;
    }
    close $fh;
    
    return @lines;
}

sub add_call {
    my ($self, $called_name, $line_num) = @_;
    push @{$self->{calls}}, {
        name => $called_name,
        line => $line_num,
    };
}

sub add_file_io {
    my ($self, $type, $target, $line_num) = @_;
    push @{$self->{file_io}}, {
        type   => $type,    # INPUT or OUTPUT
        target => $target,
        line   => $line_num,
    };
}

sub add_db_operation {
    my ($self, $operation, $table, $line_num) = @_;
    push @{$self->{db_operations}}, {
        operation => $operation,  # INSERT, UPDATE, DELETE, SELECT
        table     => $table,
        line      => $line_num,
    };
}

sub get_calls {
    my ($self) = @_;
    return @{$self->{calls}};
}

sub get_file_io {
    my ($self) = @_;
    return @{$self->{file_io}};
}

sub get_db_operations {
    my ($self) = @_;
    return @{$self->{db_operations}};
}

1;
