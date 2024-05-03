#!/bin/bash

kohaplugindir="$(grep -Po '(?<=<pluginsdir>).*?(?=</pluginsdir>)' $KOHA_CONF)"
kohadir="$(grep -Po '(?<=<intranetdir>).*?(?=</intranetdir>)' $KOHA_CONF)"

rm $kohaplugindir/Koha/Plugin/Fi/KohaSuomi/DeleteBiblioComponents.pm

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

ln -s "$SCRIPT_DIR/Koha/Plugin/Fi/KohaSuomi/DeleteBiblioComponents.pm" $kohaplugindir/Koha/Plugin/Fi/KohaSuomi/DeleteBiblioComponents.pm

perl $kohadir/misc/devel/install_plugins.pl
