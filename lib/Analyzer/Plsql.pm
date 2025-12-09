package Analyzer::Plsql;
use strict;
use warnings;
use utf8;
use parent 'Analyzer::Base';

sub analyze {
    my ($self) = @_;
    my @lines = $self->read_file();
    
    # Join all lines for preprocessing
    my $content = join('', @lines);
    
    # Remove block comments /* ... */ first
    $content =~ s|/\*.*?\*/||gs;
    
    # Protect string literals by replacing with placeholders
    $self->{strings} = [];
    $content =~ s/'([^']*(?:''[^']*)*)'/
        push @{$self->{strings}}, $1;
        "__STRING_" . $#{$self->{strings}} . "__"
    /ge;
    
    # Detect DB operations (global search for multi-line support)
    $self->detect_db_operations($content);
    
    # Detect file I/O (global search)
    $self->detect_file_io($content);
    
    # Split back into lines for line-number tracking
    @lines = split /\n/, $content;
    
    my $line_num = 0;
    foreach my $line (@lines) {
        $line_num++;
        
        # Remove SQL line comments
        $line =~ s/--.*$//;
        
        # Detect procedure/package calls
        $self->detect_calls($line, $line_num);
    }
}

sub _get_line_num {
    my ($self, $content, $pos) = @_;
    my $prefix = substr($content, 0, $pos);
    return ($prefix =~ tr/\n//) + 1;
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
    my ($self, $content) = @_;
    
    # UTL_FILE.FOPEN('directory', 'filename', 'mode')
    while ($content =~ /UTL_FILE\.FOPEN\s*\(\s*(__STRING_(\d+)__|['"][^'"]+['"])\s*,\s*(__STRING_(\d+)__|['"][^'"]+['"])/gi) {
        my $dir_raw = $1;
        my $dir_idx = $2;
        my $file_raw = $3;
        my $file_idx = $4;
        
        my $dir = defined $dir_idx ? $self->{strings}->[$dir_idx] : $dir_raw;
        my $file = defined $file_idx ? $self->{strings}->[$file_idx] : $file_raw;
        
        # Clean up quotes if raw
        $dir =~ s/^['"]|['"]$//g;
        $file =~ s/^['"]|['"]$//g;
        
        my $line_num = $self->_get_line_num($content, $-[0]);
        $self->add_file_io('FILE', "$dir/$file", $line_num);
    }
    
    # UTL_FILE operations
    while ($content =~ /UTL_FILE\.(GET_LINE|PUT_LINE|PUT|NEW_LINE)/gi) {
        my $line_num = $self->_get_line_num($content, $-[0]);
        # Note: actual file name would be in variable, hard to track
        if ($self->{logger}) {
            $self->{logger}->warn("UTL_FILE操作検出（ファイル名は変数参照）: (行: $line_num)");
        }
    }
}

sub detect_db_operations {
    my ($self, $content) = @_;
    
    # INSERT INTO table
    while ($content =~ /INSERT\s+INTO\s+([A-Z0-9_]+)/gi) {
        $self->add_db_operation('INSERT', uc($1), $self->_get_line_num($content, $-[0]));
    }
    
    # UPDATE table
    while ($content =~ /UPDATE\s+([A-Z0-9_]+)/gi) {
        $self->add_db_operation('UPDATE', uc($1), $self->_get_line_num($content, $-[0]));
    }
    
    # DELETE FROM table
    while ($content =~ /DELETE\s+FROM\s+([A-Z0-9_]+)/gi) {
        $self->add_db_operation('DELETE', uc($1), $self->_get_line_num($content, $-[0]));
    }
    
    # SELECT ... FROM table
    while ($content =~ /SELECT\s+.*\s+FROM\s+([A-Z0-9_]+)/gi) {
        $self->add_db_operation('SELECT', uc($1), $self->_get_line_num($content, $-[0]));
    }
    
    # MERGE INTO table
    while ($content =~ /MERGE\s+INTO\s+([A-Z0-9_]+)/gi) {
        $self->add_db_operation('MERGE', uc($1), $self->_get_line_num($content, $-[0]));
    }
    
    # EXECUTE IMMEDIATE (dynamic SQL)
    while ($content =~ /EXECUTE\s+IMMEDIATE/gi) {
        my $line_num = $self->_get_line_num($content, $-[0]);
        if ($self->{logger}) {
            $self->{logger}->warn("動的SQL検出（テーブル名未解決）: EXECUTE IMMEDIATE (行: $line_num)");
        }
    }
}

1;
