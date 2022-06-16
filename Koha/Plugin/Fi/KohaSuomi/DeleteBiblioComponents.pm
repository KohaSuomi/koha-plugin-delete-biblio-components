package Koha::Plugin::Fi::KohaSuomi::DeleteBiblioComponents;

use Modern::Perl;
use base qw(Koha::Plugins::Base);
use MARC::Record;

use C4::Biblio qw( DelBiblio );
use C4::Search qw( new_record_from_zebra );
use Koha::SearchEngine::Search;


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

sub after_biblio_action {
    my ( $self, $args ) = @_;

    return 1 if ($args->{action} ne 'delete');

    my $bib = $args->{biblio};

    return 1 if (!$bib);

    my $components = $bib->get_marc_components(999);

    for my $part ( @{$components} ) {
        $part = C4::Search::new_record_from_zebra( 'biblioserver', $part );
        my $id = Koha::SearchEngine::Search::extract_biblionumber( $part );
        DelBiblio($id);
    }

    return 1;
}

1;
