#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use open ':std', ':encoding(utf8)';
use File::Spec;
use File::Basename;
use Cwd 'abs_path';
use lib 'lib';

use Analyzer::Sh;
use VariableResolver;
use Output::Logger;

my $logger = Output::Logger->new(output_dir => 't/output');
my $var_resolver = VariableResolver->new(logger => $logger);
my $test_file = 't/fixtures/path_detection_test.sh';

my $analyzer = Analyzer::Sh->new(
    filepath => $test_file,
    logger => $logger,
    var_resolver => $var_resolver
);

$analyzer->analyze();

my @calls = $analyzer->get_calls();

print "パス検出テスト: $test_file\n";
print "=" x 70 . "\n";
print "検出された呼び出し:\n";
print "-" x 70 . "\n";

if (@calls) {
    foreach my $call (@calls) {
        printf "%-40s (行: %3d, 種類: %s)\n", 
            $call->{name}, 
            $call->{line}, 
            $call->{type};
    }
} else {
    print "検出された呼び出しなし\n";
}

print "\n" . "=" x 70 . "\n";
print "テストケース分析:\n";
print "-" x 70 . "\n";

my %expected = (
    2 => '/A/B/AAAA',
    5 => '/opt/batch/process',
    8 => 'SCRIPT=/usr/local/bin/myapp',  # 代入 - 呼び出しではない
    11 => '/var/scripts/job.sh',
    14 => './run_script',
    17 => '$BASE_DIR/bin/execute',
);

foreach my $line_num (sort { $a <=> $b } keys %expected) {
    my $found = grep { $_->{line} == $line_num } @calls;
    printf "行%2d: %s\n", $line_num, $found ? "✓ 検出" : "✗ 未検出";
}
