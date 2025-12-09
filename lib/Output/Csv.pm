package Output::Csv;
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

sub write_dependencies {
    my ($self, $dependencies) = @_;
    
    my $csv_file = File::Spec->catfile($self->{output_dir}, 'dependencies.csv');
    open my $fh, ">:encoding($self->{encoding})", $csv_file
        or die "Cannot create CSV file: $csv_file\n";
    
    # Header
    print $fh "起点,呼び出し元,呼び出し先,言語,階層\n";
    
    # Data rows
    foreach my $dep (@$dependencies) {
        print $fh $self->_csv_escape($dep->{entry_point}) . ",";
        print $fh $self->_csv_escape($dep->{caller}) . ",";
        print $fh $self->_csv_escape($dep->{callee}) . ",";
        print $fh $self->_csv_escape($dep->{language}) . ",";
        print $fh $dep->{depth} . "\n";
    }
    
    close $fh;
}

sub write_file_io {
    my ($self, $file_ios) = @_;
    
    my $csv_file = File::Spec->catfile($self->{output_dir}, 'file_io.csv');
    open my $fh, ">:encoding($self->{encoding})", $csv_file
        or die "Cannot create CSV file: $csv_file\n";
    
    # Header
    print $fh "ファイル,種別,対象,行番号\n";
    
    # Data rows
    foreach my $io (@$file_ios) {
        print $fh $self->_csv_escape($io->{file}) . ",";
        print $fh $self->_csv_escape($io->{type}) . ",";
        print $fh $self->_csv_escape($io->{target}) . ",";
        print $fh $io->{line} . "\n";
    }
    
    close $fh;
}

sub write_db_operations {
    my ($self, $db_ops) = @_;
    
    my $csv_file = File::Spec->catfile($self->{output_dir}, 'db_operations.csv');
    open my $fh, ">:encoding($self->{encoding})", $csv_file
        or die "Cannot create CSV file: $csv_file\n";
    
    # Header
    print $fh "ファイル,操作,テーブル名,行番号\n";
    
    # Data rows
    foreach my $op (@$db_ops) {
        print $fh $self->_csv_escape($op->{file}) . ",";
        print $fh $self->_csv_escape($op->{operation}) . ",";
        print $fh $self->_csv_escape($op->{table}) . ",";
        print $fh $op->{line} . "\n";
    }
    
    close $fh;
}

sub _csv_escape {
    my ($self, $str) = @_;
    $str //= '';
    
    # If contains comma, newline, or quote, wrap in quotes
    if ($str =~ /[,"\n\r]/) {
        $str =~ s/"/""/g;  # Escape quotes by doubling
        $str = "\"$str\"";
    }
    
    return $str;
}

1;
