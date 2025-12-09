package Output::Flowchart;
use strict;
use warnings;
use utf8;
use File::Spec;
use File::Basename;

sub new {
    my ($class, %args) = @_;
    my $self = {
        output_dir => $args{output_dir},
        encoding   => $args{encoding} // 'utf-8',
    };
    bless $self, $class;
    return $self;
}

sub write {
    my ($self, $entry_files, $dependencies) = @_;
    
    my $md_file = File::Spec->catfile($self->{output_dir}, 'flowchart.md');
    open my $fh, ">:utf8", $md_file
        or die "Cannot create flowchart file: $md_file\n";
    
    print $fh "# バッチジョブ呼び出しフロー\n\n";
    
    # Group dependencies by entry point
    my %by_entry;
    foreach my $dep (@$dependencies) {
        my $entry = $dep->{entry_point};
        push @{$by_entry{$entry}}, $dep;
    }
    
    # Generate a flowchart for each entry point
    foreach my $entry_file (@$entry_files) {
        my $deps = $by_entry{$entry_file} // [];
        
        print $fh "## 起点: $entry_file\n\n";
        print $fh "```mermaid\n";
        print $fh "flowchart TD\n";
        
        # Build node map (use full paths as keys to avoid collisions)
        my %nodes;       # path => node_id
        my %node_labels; # node_id => display label
        my $node_counter = 0;
        my %edges;
        
        # Add entry node
        my $entry_basename = basename($entry_file);
        my $entry_node_id = $self->_get_node_id(\%nodes, \$node_counter, $entry_file);
        $node_labels{$entry_node_id} = $entry_basename;
        
        # Process dependencies
        foreach my $dep (@$deps) {
            my $caller_path = $dep->{caller_path} // $dep->{caller};
            my $callee_path = $dep->{callee_path} // $dep->{callee};
            my $caller = $dep->{caller};
            my $callee = $dep->{callee};
            my $lang = $dep->{language};
            
            my $caller_id = $self->_get_node_id(\%nodes, \$node_counter, $caller_path);
            my $callee_id = $self->_get_node_id(\%nodes, \$node_counter, $callee_path);
            
            # Store display labels (basename)
            $node_labels{$caller_id} //= $caller;
            $node_labels{$callee_id} //= $callee;
            
            # Store edge
            my $edge_key = "$caller_id->$callee_id";
            $edges{$edge_key} = {
                from => $caller_id,
                to   => $callee_id,
                lang => $lang,
            };
        }
        
        # Generate node definitions
        foreach my $path (sort keys %nodes) {
            my $node_id = $nodes{$path};
            my $label = $self->_escape_mermaid($node_labels{$node_id} // basename($path));
            print $fh "    ${node_id}[$label]\n";
        }
        
        # Generate edges
        foreach my $edge_key (sort keys %edges) {
            my $edge = $edges{$edge_key};
            print $fh "    $edge->{from} --> $edge->{to}\n";
        }
        
        print $fh "```\n\n";
    }
    
    close $fh;
}

sub _get_node_id {
    my ($self, $nodes, $counter, $name) = @_;
    
    unless (exists $nodes->{$name}) {
        $nodes->{$name} = 'N' . $$counter;
        $$counter++;
    }
    
    return $nodes->{$name};
}

sub _escape_mermaid {
    my ($self, $str) = @_;
    $str //= '';
    # Escape special characters for Mermaid
    $str =~ s/"/\\"/g;
    return $str;
}

1;
