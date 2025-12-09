package Output::Json;
use strict;
use warnings;
use utf8;
use File::Spec;

# Try to use JSON::PP (standard in Perl 5.14+)
my $HAS_JSON_PP = 0;
BEGIN {
    eval {
        require JSON::PP;
        JSON::PP->import();
        $HAS_JSON_PP = 1;
    };
}

sub new {
    my ($class, %args) = @_;
    my $self = {
        output_dir => $args{output_dir},
        encoding   => $args{encoding} // 'utf-8',
    };
    bless $self, $class;
    return $self;
}

sub write {
    my ($self, $dependencies) = @_;
    
    my $json_file = File::Spec->catfile($self->{output_dir}, 'dependencies.json');
    open my $fh, ">:utf8", $json_file
        or die "Cannot create JSON file: $json_file\n";
    
    if ($HAS_JSON_PP) {
        # Use JSON::PP for proper encoding
        my $json = JSON::PP->new->utf8(0)->pretty->canonical;
        print $fh $json->encode($dependencies);
    } else {
        # Fallback to manual JSON generation
        print $fh $self->_encode_json($dependencies);
    }
    
    close $fh;
}

# Fallback manual JSON encoder
sub _encode_json {
    my ($self, $data) = @_;
    
    if (ref $data eq 'ARRAY') {
        my @items = map { $self->_encode_json($_) } @$data;
        return "[\n" . join(",\n", map { "  $_" } @items) . "\n]";
    } elsif (ref $data eq 'HASH') {
        my @pairs;
        foreach my $key (sort keys %$data) {
            my $val = $self->_encode_json($data->{$key});
            push @pairs, $self->_json_string($key) . ": " . $val;
        }
        return "{" . join(", ", @pairs) . "}";
    } elsif (!defined $data) {
        return "null";
    } elsif ($data =~ /^-?\d+$/) {
        return $data;  # Integer
    } elsif ($data =~ /^-?\d+\.\d+$/) {
        return $data;  # Float
    } else {
        return $self->_json_string($data);
    }
}

sub _json_string {
    my ($self, $str) = @_;
    $str //= '';
    
    # Escape special characters per JSON spec
    $str =~ s/\\/\\\\/g;  # Backslash first
    $str =~ s/"/\\"/g;     # Double quote
    $str =~ s/\n/\\n/g;    # Newline
    $str =~ s/\r/\\r/g;    # Carriage return
    $str =~ s/\t/\\t/g;    # Tab
    $str =~ s/\f/\\f/g;    # Form feed
    $str =~ s/\x08/\\b/g;  # Backspace
    
    # Escape control characters (U+0000 to U+001F)
    $str =~ s/([\x00-\x1f])/sprintf("\\u%04x", ord($1))/ge;
    
    return "\"$str\"";
}

1;
