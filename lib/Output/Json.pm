package Output::Json;
use strict;
use warnings;
use File::Spec;

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
    open my $fh, ">:encoding($self->{encoding})", $json_file
        or die "Cannot create JSON file: $json_file\n";
    
    # Manual JSON generation (no external modules)
    print $fh "[\n";
    
    my $count = 0;
    foreach my $dep (@$dependencies) {
        print $fh "," if $count > 0;
        print $fh "  {\n";
        print $fh "    \"entry_point\": " . $self->_json_string($dep->{entry_point}) . ",\n";
        print $fh "    \"caller\": " . $self->_json_string($dep->{caller}) . ",\n";
        print $fh "    \"callee\": " . $self->_json_string($dep->{callee}) . ",\n";
        print $fh "    \"language\": " . $self->_json_string($dep->{language}) . ",\n";
        print $fh "    \"depth\": " . $dep->{depth} . ",\n";
        print $fh "    \"caller_path\": " . $self->_json_string($dep->{caller_path}) . ",\n";
        print $fh "    \"callee_path\": " . $self->_json_string($dep->{callee_path}) . ",\n";
        print $fh "    \"line_number\": " . $dep->{line_number} . "\n";
        print $fh "  }\n";
        $count++;
    }
    
    print $fh "]\n";
    close $fh;
}

sub _json_string {
    my ($self, $str) = @_;
    $str //= '';
    $str =~ s/\\/\\\\/g;
    $str =~ s/"/\\"/g;
    $str =~ s/\n/\\n/g;
    $str =~ s/\r/\\r/g;
    $str =~ s/\t/\\t/g;
    return "\"$str\"";
}

1;
