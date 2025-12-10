#!/usr/bin/env perl
use strict;
use warnings;

my @test_cases = (
    '/A/B/AAAA',
    '/opt/batch/process',
    '/var/scripts/job.sh',
    './run_script',
    '$BASE_DIR/bin/execute',
    '    /A/B/AAAA',
    'echo "test" && /opt/batch/process',
    'something | /var/scripts/cmd',
);

print "Regex パターンテスト\n";
print "=" x 80 . "\n";

my $pattern1 = m{^\s*([/\w\-\$\{\}]+/[\w\-]+)\s*$};
my $pattern2 = m{\s+([/\w\-\$\{\}]+/[\w\-]+)\s*[;&|]};

foreach my $line (@test_cases) {
    print "入力: '$line'\n";
    
    if ($line =~ m{^\s*([/\w\-\$\{\}]+/[\w\-]+)\s*$}) {
        print "  ✓ Pattern 1 マッチ: \$1 = '$1'\n";
    } else {
        print "  ✗ Pattern 1 不一致\n";
    }
    
    if ($line =~ m{\s+([/\w\-\$\{\}]+/[\w\-]+)\s*[;&|]}) {
        print "  ✓ Pattern 2 マッチ: \$1 = '$1'\n";
    } else {
        print "  ✗ Pattern 2 不一致\n";
    }
    
    # 追加テスト: より単純なパターン
    if ($line =~ m{(/[A-Za-z0-9/_\-]+)}) {
        print "  ✓ 簡易パターン マッチ: \$1 = '$1'\n";
    }
    
    print "\n";
}
