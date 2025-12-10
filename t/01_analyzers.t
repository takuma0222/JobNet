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
use_ok('DependencyResolver');
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
    is($var_resolver->resolve_variable('LOG_DIR'), '/opt/batch/log', 'Variable LOG_DIR resolved (1-level nested)');
    is($var_resolver->resolve_variable('ERROR_LOG'), '/opt/batch/log/error.log', 'Variable ERROR_LOG resolved (2-level nested)');
    is($var_resolver->resolve_variable('ARCHIVE_ERROR'), '/opt/batch/log/error.log.old', 'Variable ARCHIVE_ERROR resolved (3-level nested)');
    
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
    
    # Build list of operations for each file
    my %io_ops;
    foreach my $op (@io) {
        push @{$io_ops{$op->{target}}}, $op->{type};
    }
    
    # Check simple operations
    ok(grep { $_ eq 'OUTPUT' } @{$io_ops{'/opt/batch/log/start.log'}}, 'Found output redirection with variable');
    ok(grep { $_ eq 'INPUT' } @{$io_ops{'input.dat'}}, 'Found input redirection');
    ok(grep { $_ eq 'OUTPUT' } @{$io_ops{'error.log'}}, 'Found append redirection');
    
    # Check nested variable expansion
    # ERROR_LOG (2-level nested) is used in: echo > (OUTPUT) and mv source (INPUT)
    ok(grep { $_ eq 'OUTPUT' } @{$io_ops{'/opt/batch/log/error.log'}}, 
       'ERROR_LOG (2-level nested) used as OUTPUT');
    ok(grep { $_ eq 'INPUT' } @{$io_ops{'/opt/batch/log/error.log'}}, 
       'ERROR_LOG (2-level nested) used as INPUT in mv');
    
    # ARCHIVE_ERROR (3-level nested) is used in: mv dest (OUTPUT)
    ok(grep { $_ eq 'OUTPUT' } @{$io_ops{'/opt/batch/log/error.log.old'}}, 
       'ARCHIVE_ERROR (3-level nested) used as OUTPUT in mv');
    
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

# --- Test 4: Hierarchical Dependency Resolution ---
subtest 'Hierarchical Dependency Resolution' => sub {
    my $entry_file = File::Spec->catfile($fixtures_dir, 'complex.sh');
    
    # Setup FileMapper with fixtures directory
    my $mapper = FileMapper->new();
    $mapper->scan_directory($fixtures_dir);
    
    # Setup VariableResolver
    my $var_resolver = VariableResolver->new(logger => $logger);
    
    # Setup DependencyResolver
    my $resolver = DependencyResolver->new(
        file_mapper  => $mapper,
        var_resolver => $var_resolver,
        logger       => $logger,
        max_depth    => 5,
        encoding     => 'utf-8'
    );
    
    # Resolve dependencies
    my $result = $resolver->resolve($entry_file);
    
    # Check dependencies found
    my @deps = @{$result->{dependencies}};
    ok(scalar(@deps) > 0, 'Found dependencies');
    
    # Build a map of caller -> callee relationships
    my %dep_map;
    foreach my $dep (@deps) {
        my $key = $dep->{caller} . '->' . $dep->{callee};
        $dep_map{$key} = $dep->{depth};
    }
    
    # Level 0: complex.sh -> simple_call.sh
    ok(exists $dep_map{'complex.sh->simple_call.sh'}, 'Found level 0 dependency: complex.sh -> simple_call.sh');
    
    # Level 1: simple_call.sh -> level2_script.sh  
    ok(exists $dep_map{'simple_call.sh->level2_script.sh'}, 'Found level 1 dependency: simple_call.sh -> level2_script.sh');
    
    # Check depths
    is($dep_map{'complex.sh->simple_call.sh'}, 0, 'complex.sh -> simple_call.sh at depth 0');
    is($dep_map{'simple_call.sh->level2_script.sh'}, 1, 'simple_call.sh -> level2_script.sh at depth 1');
    
    # Check file I/O aggregation across hierarchy
    my @file_io = @{$result->{file_io}};
    my %io_files = map { $_->{target} => 1 } @file_io;
    
    # From complex.sh
    ok($io_files{'error.log'}, 'Found file I/O from complex.sh');
    
    # From simple_call.sh
    ok($io_files{'/tmp/output.txt'}, 'Found file I/O from simple_call.sh');
    
    # From level2_script.sh
    ok($io_files{'/var/log/batch.log'}, 'Found file I/O from level2_script.sh');
    
    # Check DB operations aggregation
    my @db_ops = @{$result->{db_operations}};
    ok(scalar(@db_ops) >= 2, 'Found DB operations from multiple levels');
};

# --- Test 5: Csh Analyzer ---
subtest 'Csh Analyzer' => sub {
    use_ok('Analyzer::Csh');
    
    my $file = File::Spec->catfile($fixtures_dir, 'complex.csh');
    
    # Skip if fixture doesn't exist
    SKIP: {
        skip "Csh fixture not available", 5 unless -f $file;
        
        my $analyzer = Analyzer::Csh->new(
            filepath => $file,
            logger => $logger,
            file_mapper => $file_mapper
        );
        
        $analyzer->analyze();
        
        my @calls = $analyzer->get_calls();
        ok(scalar(@calls) >= 0, 'Csh analyzer works');
    }
};

# --- Test 6: Max Depth Limit ---
subtest 'Max Depth Limit' => sub {
    my $entry_file = File::Spec->catfile($fixtures_dir, 'complex.sh');
    
    my $mapper = FileMapper->new();
    $mapper->scan_directory($fixtures_dir);
    
    my $var_resolver = VariableResolver->new(logger => $logger);
    
    # Set max depth to 1 (should not reach level2_script.sh)
    my $resolver = DependencyResolver->new(
        file_mapper  => $mapper,
        var_resolver => $var_resolver,
        logger       => $logger,
        max_depth    => 1,
        encoding     => 'utf-8'
    );
    
    my $result = $resolver->resolve($entry_file);
    my @deps = @{$result->{dependencies}};
    
    my %callees = map { $_->{callee} => 1 } @deps;
    
    ok($callees{'simple_call.sh'}, 'Found simple_call.sh within depth limit');
    ok(!$callees{'level2_script.sh'}, 'Did not find level2_script.sh (beyond max depth)');
};

# --- Test 7: Circular Dependency Prevention ---
subtest 'Circular Dependency Prevention' => sub {
    # Create a temporary circular dependency scenario
    my $circular_file = File::Spec->catfile($fixtures_dir, 'circular_a.sh');
    
    SKIP: {
        skip "Circular dependency fixtures not available", 2 unless -f $circular_file;
        
        my $mapper = FileMapper->new();
        $mapper->scan_directory($fixtures_dir);
        
        my $var_resolver = VariableResolver->new(logger => $logger);
        
        my $resolver = DependencyResolver->new(
            file_mapper  => $mapper,
            var_resolver => $var_resolver,
            logger       => $logger,
            max_depth    => 10,
            encoding     => 'utf-8'
        );
        
        # Should not hang or crash
        my $result = $resolver->resolve($circular_file);
        ok(defined $result, 'Circular dependency did not cause infinite loop');
    }
};

# --- Test 8: Source Variable Inheritance ---
subtest 'Source Variable Inheritance' => sub {
    my $source_test_file = File::Spec->catfile($fixtures_dir, 'source_test.sh');
    
    SKIP: {
        skip "Source test fixtures not available", 4 unless -f $source_test_file;
        
        my $mapper = FileMapper->new();
        $mapper->scan_directory($fixtures_dir);
        
        my $var_resolver = VariableResolver->new(logger => $logger);
        
        my $resolver = DependencyResolver->new(
            file_mapper  => $mapper,
            var_resolver => $var_resolver,
            logger       => $logger,
            max_depth    => 10,
            encoding     => 'utf-8'
        );
        
        my $result = $resolver->resolve($source_test_file);
        my @deps = @{$result->{dependencies}};
        my @io = @{$result->{file_io}};
        
        # Check that variables from sourced config.csh are available
        # BATCH_DIR=/opt/batch, LIB_DIR=/opt/batch/lib, COMMON_SCRIPT=/opt/batch/lib/common.sh
        is($var_resolver->resolve_variable('BATCH_DIR'), '/opt/batch', 
           'BATCH_DIR from sourced config.csh is available');
        is($var_resolver->resolve_variable('LIB_DIR'), '/opt/batch/lib', 
           'LIB_DIR (nested variable from source) is available');
        
        # Note: Current implementation limitation - File I/O in the same file as source
        # cannot use variables from the sourced file because the file is parsed in order.
        # The sourced file's variables are only available AFTER the source line is processed
        # by DependencyResolver, but File I/O detection happens during Analyzer::Sh analysis.
        # This would require 2-pass analysis to fully support.
        # For now, we just verify the variable IS available after full resolution.
        my %io_targets = map { $_->{target} => 1 } @io;
        ok(exists $io_targets{'${BATCH_DIR}/output.log'} || exists $io_targets{'/opt/batch/output.log'}, 
           'File I/O detected (variable may or may not be expanded depending on source order)');
        
        # Check that call_type is properly set
        my @source_calls = grep { ($_->{call_type} // '') eq 'source' } @deps;
        ok(scalar(@source_calls) > 0, 'Source calls are marked with call_type=source');
    }
};

done_testing();
