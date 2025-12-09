package Analyzer::Plsql;
use strict;
use warnings;
use parent 'Analyzer::Base';

sub analyze {
    my ($self) = @_;
    my @lines = $self->read_file();
    
    # Join all lines for preprocessing
    my $content = join('', @lines);
    
    # Remove block comments /* ... */ first
    $content =~ s|/\*.*?\*/||gs;
    
    # Protect string literals by replacing with placeholders
    my @strings;
    $content =~ s/'([^']*(?:''[^']*)*)'/
        push @strings, $1;
        "__STRING_" . $#strings . "__"
    /ge;
    
    # Split back into lines for line-number tracking
    @lines = split /\n/, $content;
    
    my $line_num = 0;
    foreach my $line (@lines) {
        $line_num++;
        
        # Remove SQL line comments
        $line =~ s/--.*$//;
        
        # Detect procedure/package calls
        $self->detect_calls($line, $line_num);
        
        # Detect file I/O (UTL_FILE)
        $self->detect_file_io($line, $line_num);
        
        # Detect DB operations
        $self->detect_db_operations($line, $line_num);
    }
}

sub detect_calls {
    my ($self, $line, $line_num) = @_;
    
    # EXECUTE procedure_name or EXEC procedure_name
    if ($line =~ /(?:EXECUTE|EXEC)\s+([A-Z0-9_\.]+)/i) {
        my $proc = uc($1);  # Normalize to uppercase
        unless ($proc =~ /^IMMEDIATE$/i) {  # Skip EXECUTE IMMEDIATE
            $self->add_call($proc, $line_num);
        }
    }
    
    # Package.procedure() call
    if ($line =~ /([A-Z0-9_]+\.[A-Z0-9_]+)\s*\(/i) {
        $self->add_call(uc($1), $line_num);  # Normalize to uppercase
    }
    
    # Simple procedure call: procedure_name(args)
    if ($line =~ /^\s*([A-Z0-9_]+)\s*\(/i) {
        my $proc = uc($1);  # Normalize to uppercase
        # Exclude SQL keywords
        unless ($proc =~ /^(?:INSERT|UPDATE|DELETE|SELECT|CREATE|ALTER|DROP|IF|WHILE|FOR|LOOP|BEGIN|END|DECLARE|EXCEPTION|RETURN|CASE|WHEN)$/) {
            $self->add_call($proc, $line_num);
        }
    }
}

sub detect_file_io {
    my ($self, $line, $line_num) = @_;
    
    # UTL_FILE.FOPEN('directory', 'filename', 'mode')
    if ($line =~ /UTL_FILE\.FOPEN\s*\(\s*['"]+([^'"]+)['"]+\s*,\s*['"]+([^'"]+)['"]+/i) {
        my $dir = $1;
        my $file = $2;
        $self->add_file_io('FILE', "$dir/$file", $line_num);
    }
    
    # UTL_FILE operations
    if ($line =~ /UTL_FILE\.(GET_LINE|PUT_LINE|PUT|NEW_LINE)/i) {
        # Note: actual file name would be in variable, hard to track
        if ($self->{logger}) {
            $self->{logger}->warn("UTL_FILE操作検出（ファイル名は変数参照）: (行: $line_num)");
        }
    }
}

sub detect_db_operations {
    my ($self, $line, $line_num) = @_;
    
    # INSERT INTO table
    if ($line =~ /INSERT\s+INTO\s+([A-Z0-9_]+)/i) {
        $self->add_db_operation('INSERT', uc($1), $line_num);
    }
    
    # UPDATE table
    if ($line =~ /UPDATE\s+([A-Z0-9_]+)/i) {
        $self->add_db_operation('UPDATE', uc($1), $line_num);
    }
    
    # DELETE FROM table
    if ($line =~ /DELETE\s+FROM\s+([A-Z0-9_]+)/i) {
        $self->add_db_operation('DELETE', uc($1), $line_num);
    }
    
    # SELECT ... FROM table
    if ($line =~ /SELECT\s+.*\s+FROM\s+([A-Z0-9_]+)/i) {
        $self->add_db_operation('SELECT', uc($1), $line_num);
    }
    
    # MERGE INTO table
    if ($line =~ /MERGE\s+INTO\s+([A-Z0-9_]+)/i) {
        $self->add_db_operation('MERGE', uc($1), $line_num);
    }
    
    # EXECUTE IMMEDIATE (dynamic SQL)
    if ($line =~ /EXECUTE\s+IMMEDIATE/i) {
        if ($self->{logger}) {
            $self->{logger}->warn("動的SQL検出（テーブル名未解決）: EXECUTE IMMEDIATE (行: $line_num)");
        }
    }
}

1;
