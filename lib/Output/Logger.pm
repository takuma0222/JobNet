package Output::Logger;
use strict;
use warnings;
use File::Spec;
use IO::Handle;

sub new {
    my ($class, %args) = @_;
    my $output_dir = $args{output_dir};
    my $encoding = $args{encoding} // 'utf-8';
    
    my $log_file = File::Spec->catfile($output_dir, 'analysis.log');
    open my $fh, ">:utf8", $log_file
        or die "Cannot create log file: $log_file\n";
    
    my $self = {
        fh            => $fh,
        warning_count => 0,
    };
    bless $self, $class;
    return $self;
}

sub info {
    my ($self, $message) = @_;
    my $timestamp = $self->_timestamp();
    print {$self->{fh}} "[$timestamp] [INFO] $message\n";
    $self->{fh}->flush();
}

sub warn {
    my ($self, $message) = @_;
    my $timestamp = $self->_timestamp();
    print {$self->{fh}} "[$timestamp] [WARN] $message\n";
    $self->{fh}->flush();
    $self->{warning_count}++;
}

sub error {
    my ($self, $message) = @_;
    my $timestamp = $self->_timestamp();
    print {$self->{fh}} "[$timestamp] [ERROR] $message\n";
    $self->{fh}->flush();
}

sub warning_count {
    my ($self) = @_;
    return $self->{warning_count};
}

sub _timestamp {
    my ($self) = @_;
    my ($sec, $min, $hour, $mday, $mon, $year) = localtime(time);
    return sprintf("%04d-%02d-%02d %02d:%02d:%02d",
        $year + 1900, $mon + 1, $mday, $hour, $min, $sec);
}

sub DESTROY {
    my ($self) = @_;
    close $self->{fh} if $self->{fh};
}

1;
