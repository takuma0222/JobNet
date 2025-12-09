package Analyzer::Cobol;
use strict;
use warnings;
use parent 'Analyzer::Base';

sub analyze {
    my ($self) = @_;
    my @lines = $self->read_file();
    
    my $line_num = 0;
    my $in_exec_sql = 0;
    my $sql_buffer = '';
    
    foreach my $line (@lines) {
        $line_num++;
        
        # Remove COBOL comments:
        # - asterisk (*) in column 7 (comment line)
        # - slash (/) in column 7 (page break/comment)
        # - D in column 7 (debug line, treated as comment)
        next if length($line) >= 7 && substr($line, 6, 1) =~ /[*\/D]/;
        
        # Remove inline comments (*> format, COBOL 2002+)
        $line =~ s/\*>.*$//;
        
        # Detect CALL statements
        $self->detect_calls($line, $line_num);
        
        # Detect COPY statements (copybook dependencies)
        $self->detect_copy($line, $line_num);
        
        # Detect file I/O (SELECT ... ASSIGN TO)
        $self->detect_file_io($line, $line_num);
        
        # Detect embedded SQL
        if ($line =~ /EXEC\s+SQL/i) {
            $in_exec_sql = 1;
            $sql_buffer = $line;
        } elsif ($in_exec_sql) {
            $sql_buffer .= ' ' . $line;
            if ($line =~ /END-EXEC/i) {
                $self->detect_db_operations($sql_buffer, $line_num);
                $in_exec_sql = 0;
                $sql_buffer = '';
            }
        }
    }
}

sub detect_copy {
    my ($self, $line, $line_num) = @_;
    
    # COPY copybook-name. or COPY copybook-name OF library-name.
    if ($line =~ /COPY\s+([A-Z0-9\-_]+)/i) {
        my $copybook = $1;
        $self->add_call($copybook, $line_num);
        if ($self->{logger}) {
            $self->{logger}->info("COPY句検出: $copybook (行: $line_num)");
        }
    }
}

sub detect_calls {
    my ($self, $line, $line_num) = @_;
    
    # CALL 'PROGRAM-NAME' or CALL "PROGRAM-NAME"
    if ($line =~ /CALL\s+['"]+([A-Z0-9\-_]+)['"]+/i) {
        $self->add_call($1, $line_num);
    }
    
    # CALL WS-PROGRAM (variable CALL - note as warning)
    if ($line =~ /CALL\s+([A-Z0-9\-_]+)(?:\s|$)/i && $line !~ /['"]/) {
        my $var = $1;
        if ($self->{logger}) {
            $self->{logger}->warn("変数経由のCALL検出（未解決）: $var (行: $line_num)");
        }
    }
}

sub detect_file_io {
    my ($self, $line, $line_num) = @_;
    
    # SELECT file-name ASSIGN TO external-name
    if ($line =~ /SELECT\s+([A-Z0-9\-_]+)\s+ASSIGN\s+TO\s+(['"]?[A-Z0-9\-_.]+(?:['"])?)/i) {
        my $internal = $1;
        my $external = $2;
        
        # Remove trailing dot if present (COBOL statement terminator)
        $external =~ s/\.$//;
        
        # Determine if INPUT or OUTPUT based on file usage (simplified)
        # In real COBOL, need to check OPEN statement
        $self->add_file_io('FILE', $external, $line_num);
    }
}

sub detect_db_operations {
    my ($self, $sql_text, $line_num) = @_;
    
    # INSERT INTO table
    if ($sql_text =~ /INSERT\s+INTO\s+([A-Z0-9_]+)/i) {
        $self->add_db_operation('INSERT', $1, $line_num);
    }
    
    # UPDATE table
    if ($sql_text =~ /UPDATE\s+([A-Z0-9_]+)/i) {
        $self->add_db_operation('UPDATE', $1, $line_num);
    }
    
    # DELETE FROM table
    if ($sql_text =~ /DELETE\s+FROM\s+([A-Z0-9_]+)/i) {
        $self->add_db_operation('DELETE', $1, $line_num);
    }
    
    # SELECT ... FROM table
    if ($sql_text =~ /SELECT\s+.*\s+FROM\s+([A-Z0-9_]+)/i) {
        $self->add_db_operation('SELECT', $1, $line_num);
    }
    
    # EXECUTE IMMEDIATE (dynamic SQL warning)
    if ($sql_text =~ /EXECUTE\s+IMMEDIATE/i) {
        if ($self->{logger}) {
            $self->{logger}->warn("動的SQL検出（テーブル名未解決）: EXECUTE IMMEDIATE (行: $line_num)");
        }
    }
}

1;
