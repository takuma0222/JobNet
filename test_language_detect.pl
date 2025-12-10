#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use open ':std', ':encoding(utf8)';
use File::Spec;
use File::Basename;
use Cwd 'abs_path';
use lib 'lib';

use LanguageDetector;

my $fixtures_dir = abs_path('t/fixtures');

my @test_files = (
    'job.jcl',      # no recognized extension, has csh shebang
    'a.out',        # no recognized extension, has sh shebang
    'EXE',          # no extension, has cobol content
    'complex.sh',   # .sh extension
    'config.csh',   # .csh extension
);

my $detector = LanguageDetector->new();

print "言語判定テスト\n";
print "=" x 70 . "\n";
printf "%-25s => %-20s %s\n", "ファイル名", "判定結果", "判定方法";
print "=" x 70 . "\n";

foreach my $file (@test_files) {
    my $filepath = File::Spec->catfile($fixtures_dir, $file);
    
    if (-f $filepath) {
        my $lang = $detector->detect($filepath, 'utf-8');
        my $method = _get_method($filepath, $lang);
        printf "%-25s => %-20s %s\n", $file, ($lang // 'UNKNOWN'), $method;
    } else {
        printf "%-25s => %-20s %s\n", $file, 'ファイルなし', '';
    }
}

print "\n" . "=" x 70 . "\n";
print "判定ロジック（優先順位）:\n";
print "1. 拡張子で判定（.sh, .bash, .csh, .cbl, .cob, .pls, .sql）\n";
print "2. Shebanで判定（#!/bin/sh, #!/bin/csh, など）\n";
print "3. 内容パターンで判定（IDENTIFICATION DIVISION など）\n";
print "4. 実行可能ファイル（-x）ならsh\n";
print "5. それ以外はUNKNOWN\n";
print "=" x 70 . "\n";

sub _get_method {
    my ($filepath, $lang) = @_;
    return '' unless defined $lang;
    
    # 拡張子チェック
    if ($filepath =~ /\.(sh|bash|csh|tcsh|cbl|cob|pls|sql)$/i) {
        return "（拡張子判定）";
    }
    
    # Shebangとコンテンツチェック
    return "（Shebang/内容判定）";
}
