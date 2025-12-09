use strict;
use warnings;
use Test::More;
use File::Spec;
use File::Basename;
use Cwd 'abs_path';
use lib 'lib';

# Load modules
use_ok('Analyzer::Sh');
use_ok('Analyzer::Plsql');
use_ok('Analyzer::Cobol');
use_ok('VariableResolver');
use_ok('FileMapper');
use_ok('Output::Logger');

# Setup common objects
my $fixtures_dir = File::Spec->catdir(dirname(abs_path($0)), 'fixtures');
my $logger = Output::Logger->new(output_dir => 't/output'); # Dummy output
my $file_mapper = FileMapper->new();

# --- Test 1: Shell Analyzer ---
subtest 'Shell Analyzer' => sub {
    my $file = File::Spec->catfile($fixtures_dir, 'complex.sh');
    
    # Setup VariableResolver
    my $var_resolver = VariableResolver->new(logger => $logger);
    
    my $analyzer = Analyzer::Sh->new(
        filepath => $file,
        logger => $logger,
        file_mapper => $file_mapper,
        var_resolver => $var_resolver
    );
    
    $analyzer->analyze();
    
    # Check Variables
    is($var_resolver->resolve_variable('BASE_DIR'), '/opt/batch', 'Variable BASE_DIR resolved');
    is($var_resolver->resolve_variable('LOG_DIR'), '/opt/batch/log', 'Variable LOG_DIR resolved (recursive)');
    
    # Check Calls
    my @calls = $analyzer->get_calls();
    my %calls_map = map { $_->{name} => 1 } @calls;
    
    ok($calls_map{'/opt/batch/lib/common.sh'}, 'Found source call with variable expansion');
    ok($calls_map{'./simple_call.sh'}, 'Found simple call');
    ok($calls_map{'/opt/batch/jobs/daily_job.sh'}, 'Found variable call');
    
    ok(!$calls_map{'./fake_script.sh'}, 'Ignored call in here-document');
    ok(!$calls_map{'fake_lib.sh'}, 'Ignored source in here-document');
    ok(!$calls_map{'./string_script.sh'}, 'Ignored call in string');
    
    # Check File I/O
    my @io = $analyzer->get_file_io();
    my %io_map = map { $_->{target} => $_->{type} } @io;
    
    is($io_map{'/opt/batch/log/start.log'}, 'OUTPUT', 'Found output redirection with variable');
    is($io_map{'input.dat'}, 'INPUT', 'Found input redirection');
    is($io_map{'error.log'}, 'OUTPUT', 'Found append redirection');
    
    # Check DB Ops
    my @db = $analyzer->get_db_operations();
    ok(scalar(@db) > 0, 'Found DB operations');
};

# --- Test 2: PL/SQL Analyzer ---
subtest 'PL/SQL Analyzer' => sub {
    my $file = File::Spec->catfile($fixtures_dir, 'complex.sql');
    my $analyzer = Analyzer::Plsql->new(
        filepath => $file,
        logger => $logger,
        file_mapper => $file_mapper
    );
    
    $analyzer->analyze();
    
    # Check Calls
    my @calls = $analyzer->get_calls();
    my %calls_map = map { $_->{name} => 1 } @calls;
    
    ok($calls_map{'PKG_UTIL.LOG_START'}, 'Found package call (normalized)');
    ok(!$calls_map{'FAKE_PROC'}, 'Ignored call in block comment');
    ok(!$calls_map{'DANGEROUS_PROC'}, 'Ignored call in string literal');
    
    # Check DB Ops
    my @db = $analyzer->get_db_operations();
    my %db_map = map { $_->{table} . ':' . $_->{operation} => 1 } @db;
    
    ok($db_map{'EMP_TABLE:INSERT'}, 'Found INSERT');
    ok($db_map{'DEPT_TABLE:UPDATE'}, 'Found UPDATE');
    ok(!$db_map{'FAKE_TABLE:SELECT'}, 'Ignored SELECT in block comment');
    ok(!$db_map{'SECRET_TABLE:SELECT'}, 'Ignored SELECT in string literal');
    
    # Check File I/O
    my @io = $analyzer->get_file_io();
    ok(scalar(@io) > 0, 'Found UTL_FILE operation');
};

# --- Test 3: COBOL Analyzer ---
subtest 'COBOL Analyzer' => sub {
    my $file = File::Spec->catfile($fixtures_dir, 'complex.cbl');
    my $analyzer = Analyzer::Cobol->new(
        filepath => $file,
        logger => $logger,
        file_mapper => $file_mapper
    );
    
    $analyzer->analyze();
    
    # Check Calls
    my @calls = $analyzer->get_calls();
    my %calls_map = map { $_->{name} => 1 } @calls;
    
    ok($calls_map{'MY-COPYBOOK'}, 'Found COPY statement');
    ok($calls_map{'REAL-PROG'}, 'Found CALL statement');
    ok(!$calls_map{'FAKE-PROG'}, 'Ignored commented CALL');
    ok(!$calls_map{'FAKE-INLINE'}, 'Ignored inline commented CALL');
    
    # Check DB Ops
    my @db = $analyzer->get_db_operations();
    my %db_map = map { $_->{table} . ':' . $_->{operation} => 1 } @db;
    
    ok($db_map{'DB_TABLE:SELECT'}, 'Found Embedded SQL SELECT');
    
    # Check File I/O
    my @io = $analyzer->get_file_io();
    my %io_map = map { $_->{target} => 1 } @io;
    
    ok($io_map{"'INPUT.DAT'"}, 'Found SELECT ASSIGN literal');
    ok($io_map{'OUT-DAT'}, 'Found SELECT ASSIGN variable');
};

done_testing();
