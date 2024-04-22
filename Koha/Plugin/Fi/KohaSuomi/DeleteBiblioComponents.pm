package Koha::Plugin::Fi::KohaSuomi::DeleteBiblioComponents;

use Modern::Perl;
use base qw(Koha::Plugins::Base);
use MARC::Record;
use Encode qw( encode_utf8 );

use C4::Context;
use C4::Biblio qw( DelBiblio GetMarcFromKohaField );
use C4::Search qw( new_record_from_zebra );
use Koha::Biblios;
use Koha::Old::Biblios;
use Koha::SearchEngine;
use Koha::SearchEngine::Search;
use Koha::SearchEngine::QueryBuilder;


our $metadata = {
    name            => 'Delete Biblio Components',
    author          => 'Pasi Kallinen',
    date_authored   => '2022-06-16',
    date_updated    => "2022-06-16",
    minimum_version => '19.05.00.000',
    maximum_version => undef,
    version         => '0.0.1',
    description     => 'When deleting a biblio record, automatically delete the component biblios',
};

sub new {
    my ( $class, $args ) = @_;

    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    my $self = $class->SUPER::new($args);

    return $self;
}

sub install {
    my ( $self, $args ) = @_;

    return 1;
}

sub upgrade {
    my ( $self, $args ) = @_;

    return 1;
}

sub uninstall() {
    my ( $self, $args ) = @_;

    return 1;
}

sub _getComponentParts {
    my ($parentsField001, $parentsField003) = @_;

    my $parentrecord;

    if (ref $parentsField001 eq 'MARC::Record') {
        $parentrecord = $parentsField001;

        $parentsField003 = $parentrecord->field('003');
        $parentsField003 = $parentsField003->data() if $parentsField003;
        $parentsField001 = $parentrecord->field('001');
        $parentsField001 = $parentsField001->data() if $parentsField001;
    }

    # N.B. The query format has been carefully crafted to work with both Zebra and Elasticsearch...
    my $searchstr;
    if ($parentsField001 && $parentsField003) {
        $searchstr = "(";
        $searchstr .= "(";
        $searchstr .= "(rcn:" . $parentsField001 . " AND cni:" . $parentsField003 . ")";
        $searchstr .= " OR rcn:\"" . $parentsField003 . " " . $parentsField001 . "\"";
        $searchstr .= ")";

        # limit to monograph and serial component part records
        $searchstr .= " AND (bib-level:a OR bib-level:b)";
        $searchstr .= ")";
    }
    #elsif ($parentsField001) {
        #$query = "rcn,ext:\"$parentsField001\"";
    #}
    else {
        warn "PLUGIN DeleteBiblioComponents: Record with no field 001 or no 003 encountered!" unless $parentrecord;
    }

    my @componentXMLs;
    my $resultSetSize = 0;
    my $error;

    if (defined($searchstr)) {
        # warn "SEARCHSTR:$searchstr";
        my $max_results = 1000;
        my $components;
        my $searcher = Koha::SearchEngine::Search->new({index => $Koha::SearchEngine::BIBLIOS_INDEX});
        my ( $error, $results, $total_hits );
        eval {
            ( $error, $results, $total_hits ) = $searcher->simple_search_compat( $searchstr, 0, $max_results );
        };
        if( $error || $@ ) {
            $error //= q{};
            $error .= $@ if $@;
            warn "Warning from simple_search_compat: '$error'";
        }


        if ($results) {
            my $marcflavour = C4::Context->preference('marcflavour');
            my $parts;
            for my $part ( @{$results} ) {
                #warn "part: $part";

                push @componentXMLs, ref($part) eq 'MARC::Record' ? encode_utf8($part->as_xml_record($marcflavour)) : $part;
                $resultSetSize = $results;
            }
        } else {
            # warn "no results...";
        }

    }
    return ($parentsField001, $parentsField003, $parentrecord, $error, \@componentXMLs, $resultSetSize, $searchstr);
}


sub getComponentBiblionumbers {
    my ($parentsField001, $parentsField003, $parentrecord, $error, $componentPartRecordXMLs, $resultSetSize) = _getComponentParts(@_);

    my ( $tagid, $subfieldid ) = GetMarcFromKohaField( "biblio.biblionumber" );

    my @componentNumbers;
    if ($resultSetSize && !$error) {
        foreach my $componentRecordXML (@$componentPartRecordXMLs) {
            if ($componentRecordXML =~ /<(data|control)field tag="$tagid".*?>(.*?)<\/(data|control)field>/s) {
                my $fieldStr = $2;
                if ($fieldStr =~ /<subfield code="$subfieldid">(.*?)<\/subfield>/) {
                    my $biblionumber = $1;
                    push @componentNumbers, $biblionumber;
                }
            }
        }
    }
    return \@componentNumbers;
}

sub delComponentBiblios {
    my ($biblionumber) = @_;
    # can't use GetMarcBiblio - the record has already been deleted.
    # my $record = GetMarcBiblio({ biblionumber => $biblionumber });
    my @removalErrors;

    my $sth = C4::Context->dbh->prepare("SELECT * FROM deletedbiblio_metadata WHERE biblionumber = ?");
    $sth->execute($biblionumber);
    my $res = $sth->fetchrow_hashref();
    my $marcxml = $res->{metadata};
    my $record = MARC::Record->new_from_xml($marcxml, 'UTF-8', 'MARC21');

    my $ldr7 = substr($record->leader(), 7, 1);

    # shortcut, so we don't call search for components of components (leader/7 is a or b)
    return undef if ($ldr7 =~ /[ab]/ );

    #warn "Got host record (bn=$biblionumber) w 001: ".$record->field('001')->data();

    foreach my $componentPartBiblionumber (  @{ getComponentBiblionumbers( $record )}  ) {
        next if ($biblionumber == $componentPartBiblionumber);
        # warn "Got component record: $componentPartBiblionumber";
        my $error = DelBiblio($componentPartBiblionumber);
        #if ($error) {
        #    my $html = "<a href='/cgi-bin/koha/catalogue/detail.pl?biblionumber=$componentPartBiblionumber'>$componentPartBiblionumber</a>";
        #    push(@removalErrors, $html.' : '.$error);
        #}
    }
    #if (@removalErrors) {
    #    return join("\n", @removalErrors);
    #}
    return undef;
}

# this is hacky, because after_biblio_action is called after the host biblio is deleted.
# we need to get the deleted marc record, and we can't use get_marc_components() on it.

sub after_biblio_action {
    my ( $self, $args ) = @_;

    #warn "after_biblio_action BEGIN";

    return 1 if ($args->{action} ne 'delete');

    #warn "action == delete";

    #my $bib = $args->{biblio};
    my $bn = $args->{biblio_id} || undef;

    # FIXME: any way to return $error to user?
    my $error = delComponentBiblios($bn);

    #if (!$bib && $bn) {
    #$bib = Koha::Biblios->find($bn);
    #    warn "tried to find bib via bn";
    #}

    #if (!$bib && $bn) {
    #    my $sth = C4::Context->dbh->prepare("SELECT * FROM deletedbiblio_metadata WHERE biblionumber = ?");
    #    $sth->execute($bn);
    #    my $res = $sth->fetchrow_hashref();
    #    my $marcxml = $res->{metadata};
    #    warn "GOT marcxml" if ($marcxml);
    #}

    #if ($bib) {
    #    my $components = $bib->get_marc_components(999);
    #
    #    for my $part ( @{$components} ) {
    #        $part = C4::Search::new_record_from_zebra( 'biblioserver', $part );
    #        my $id = Koha::SearchEngine::Search::extract_biblionumber( $part );
    #        warn "after_biblio_action: id=$id";
    #        DelBiblio($id);
    #    }
    #}
    #warn "after_biblio_action END";

    return 1;
}

1;
