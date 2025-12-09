#!/usr/bin/env perl
use strict;
use warnings;
use Getopt::Long;
use File::Basename;
use File::Spec;
use Cwd 'abs_path';

# Add lib directory to @INC
BEGIN {
    my $lib_dir = File::Spec->catdir(dirname(abs_path($0)), 'lib');
    unshift @INC, $lib_dir;
}

use LanguageDetector;
use DependencyResolver;
use FileMapper;
use VariableResolver;
use Output::Logger;
use Output::Json;
use Output::Csv;
use Output::Flowchart;

# Parse command line options
my $input_file = '';
my $output_dir = '';
my $max_depth = 10;
my $encoding = 'utf-8';
my @env_vars = ();
my $env_file = '';
my @search_dirs_cli = ();

GetOptions(
    'input=s'      => \$input_file,
    'output=s'     => \$output_dir,
    'max-depth=i'  => \$max_depth,
    'encoding=s'   => \$encoding,
    'env=s@'       => \@env_vars,
    'env-file=s'   => \$env_file,
    'search-dir=s@' => \@search_dirs_cli,
) or die "Usage: $0 --input FILE --output DIR [--max-depth N] [--encoding ENC] [--env VAR=VALUE] [--env-file FILE] [--search-dir DIR]\n";

die "Error: --input is required\n" unless $input_file;
die "Error: --output is required\n" unless $output_dir;
die "Error: Input file does not exist: $input_file\n" unless -f $input_file;

# Create output directory if it doesn't exist
unless (-d $output_dir) {
    mkdir $output_dir or die "Error: Cannot create output directory: $output_dir\n";
}

# Initialize logger
my $logger = Output::Logger->new(
    output_dir => $output_dir,
    encoding   => $encoding
);

$logger->info("解析開始: " . localtime());
$logger->info("入力ファイル: $input_file");
$logger->info("出力ディレクトリ: $output_dir");
$logger->info("最大深度: $max_depth");

# Parse environment variables from CLI
my %cli_vars = ();

# Parse --env options
foreach my $env_var (@env_vars) {
    if ($env_var =~ /^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/) {
        $cli_vars{$1} = $2;
        $logger->info("環境変数設定(CLI): $1=$2");
    } else {
        $logger->warn("環境変数の形式が不正です: $env_var");
    }
}

# Parse --env-file if specified
if ($env_file && -f $env_file) {
    $logger->info("環境変数ファイル読み込み: $env_file");
    open my $env_fh, "<:encoding($encoding)", $env_file
        or die "Error: Cannot open env file: $env_file\n";
    while (my $line = <$env_fh>) {
        chomp $line;
        $line =~ s/^\s+|\s+$//g;  # trim whitespace
        next if $line eq '' || $line =~ /^#/;  # skip empty lines and comments
        
        if ($line =~ /^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/) {
            $cli_vars{$1} = $2;
            $logger->info("環境変数設定(ファイル): $1=$2");
        } else {
            $logger->warn("環境変数の形式が不正です: $line");
        }
    }
    close $env_fh;
} elsif ($env_file) {
    $logger->warn("環境変数ファイルが見つかりません: $env_file");
}

# Initialize VariableResolver
my $var_resolver = VariableResolver->new(
    cli_vars => \%cli_vars,
    logger   => $logger
);

# Read input file list
$logger->info("起点ファイルリスト読み込み中...");
open my $fh, "<:encoding($encoding)", $input_file 
    or die "Error: Cannot open input file: $input_file\n";
my @entry_files;
while (my $line = <$fh>) {
    chomp $line;
    $line =~ s/^\s+|\s+$//g;  # trim whitespace
    next if $line eq '' || $line =~ /^#/;  # skip empty lines and comments
    push @entry_files, $line;
}
close $fh;

$logger->info("対象ファイル数: " . scalar(@entry_files));

# Initialize file mapper
my $file_mapper = FileMapper->new();

# Scan for all script files in search directories
$logger->info("ファイルマッピング構築中...");
my @search_dirs;
if (@search_dirs_cli) {
    @search_dirs = @search_dirs_cli;
    $logger->info("検索ディレクトリ(CLI指定): " . join(', ', @search_dirs));
} else {
    @search_dirs = (
        '/opt/batch',
        '/usr/local/cobol',
        '/home/app',
        '/var/scripts',
    );
    $logger->info("検索ディレクトリ(デフォルト): " . join(', ', @search_dirs));
}

foreach my $dir (@search_dirs) {
    if (-d $dir) {
        $file_mapper->scan_directory($dir);
    } else {
        $logger->warn("検索ディレクトリが存在しません: $dir");
    }
}

# Add entry files to mapper
foreach my $file (@entry_files) {
    $file_mapper->add_file($file);
}

# Initialize dependency resolver
my $resolver = DependencyResolver->new(
    file_mapper  => $file_mapper,
    var_resolver => $var_resolver,
    logger       => $logger,
    max_depth    => $max_depth,
    encoding     => $encoding
);

# Analyze all entry files
my $all_dependencies = [];
my $all_file_io = [];
my $all_db_ops = [];

foreach my $entry_file (@entry_files) {
    unless (-f $entry_file) {
        $logger->warn("起点ファイルが見つかりません: $entry_file");
        next;
    }
    
    $logger->info("解析中: $entry_file");
    
    my $result = $resolver->resolve($entry_file);
    
    push @$all_dependencies, @{$result->{dependencies}};
    push @$all_file_io, @{$result->{file_io}};
    push @$all_db_ops, @{$result->{db_operations}};
}

# Generate outputs
$logger->info("出力ファイル生成中...");

# JSON output
my $json_writer = Output::Json->new(
    output_dir => $output_dir,
    encoding   => $encoding
);
$json_writer->write($all_dependencies);
$logger->info("生成: dependencies.json");

# CSV outputs
my $csv_writer = Output::Csv->new(
    output_dir => $output_dir,
    encoding   => $encoding
);
$csv_writer->write_dependencies($all_dependencies);
$logger->info("生成: dependencies.csv");

$csv_writer->write_file_io($all_file_io);
$logger->info("生成: file_io.csv");

$csv_writer->write_db_operations($all_db_ops);
$logger->info("生成: db_operations.csv");

# Flowchart output
my $flowchart_writer = Output::Flowchart->new(
    output_dir => $output_dir,
    encoding   => $encoding
);
$flowchart_writer->write(\@entry_files, $all_dependencies);
$logger->info("生成: flowchart.md");

# Summary
$logger->info("--- サマリー ---");
$logger->info("解析ファイル数: " . scalar(keys %{$resolver->analyzed_files}));
$logger->info("検出した依存関係: " . scalar(@$all_dependencies));
$logger->info("ファイルI/O: " . scalar(@$all_file_io));
$logger->info("DB操作: " . scalar(@$all_db_ops));
$logger->info("警告: " . $logger->warning_count);

# Write summary to file
my $summary_file = File::Spec->catfile($output_dir, 'summary.txt');
open my $sum_fh, ">:encoding($encoding)", $summary_file
    or die "Error: Cannot create summary file: $summary_file\n";
print $sum_fh "バッチジョブフロー解析 サマリー\n";
print $sum_fh "=" x 50 . "\n\n";
print $sum_fh "解析日時: " . localtime() . "\n";
print $sum_fh "起点ファイル数: " . scalar(@entry_files) . "\n";
print $sum_fh "解析ファイル数: " . scalar(keys %{$resolver->analyzed_files}) . "\n";
print $sum_fh "検出した依存関係: " . scalar(@$all_dependencies) . "\n";
print $sum_fh "ファイルI/O: " . scalar(@$all_file_io) . "\n";
print $sum_fh "DB操作: " . scalar(@$all_db_ops) . "\n";
print $sum_fh "警告数: " . $logger->warning_count . "\n";
close $sum_fh;

$logger->info("生成: summary.txt");
$logger->info("解析完了");

print "解析が完了しました。出力ディレクトリ: $output_dir\n";
