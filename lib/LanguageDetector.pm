package LanguageDetector;
use strict;
use warnings;

sub new {
    my $class = shift;
    my $self = {};
    bless $self, $class;
    return $self;
}

sub detect {
    my ($self, $filepath, $encoding) = @_;
    $encoding //= 'utf-8';
    
    # Check by extension first
    if ($filepath =~ /\.sh$/) {
        return 'sh';
    } elsif ($filepath =~ /\.bash$/) {
        return 'sh';
    } elsif ($filepath =~ /\.csh$/) {
        return 'csh';
    } elsif ($filepath =~ /\.tcsh$/) {
        return 'csh';
    } elsif ($filepath =~ /\.cbl$/i) {
        return 'cobol';
    } elsif ($filepath =~ /\.cob$/i) {
        return 'cobol';
    } elsif ($filepath =~ /\.pls$/i) {
        return 'plsql';
    } elsif ($filepath =~ /\.sql$/i) {
        return 'plsql';
    }
    
    # Check by shebang and content
    return undef unless -f $filepath;
    
    open my $fh, "<:encoding($encoding)", $filepath or return undef;
    
    # Read first few lines
    my $header = '';
    for (my $i = 0; $i < 10 && !eof($fh); $i++) {
        my $line = <$fh>;
        $header .= $line;
    }
    close $fh;
    
    # Check shebang (support /bin/*, /usr/bin/*, and /usr/bin/env patterns)
    if ($header =~ m{^#!\s*(?:/usr)?/bin/(?:env\s+)?(?:ba)?sh}m || 
        $header =~ m{^#!\s*(?:/usr)?/bin/(?:env\s+)?ksh}m) {
        return 'sh';
    } elsif ($header =~ m{^#!\s*(?:/usr)?/bin/(?:env\s+)?(?:t)?csh}m) {
        return 'csh';
    }
    
    # Check content patterns
    if ($header =~ /IDENTIFICATION\s+DIVISION/i) {
        return 'cobol';
    } elsif ($header =~ /PROCEDURE\s+\w+\s+IS/i || $header =~ /CREATE\s+OR\s+REPLACE\s+PROCEDURE/i) {
        return 'plsql';
    }
    
    # Default to sh for executable files without extension
    if (-x $filepath) {
        return 'sh';
    }
    
    return undef;
}

1;
