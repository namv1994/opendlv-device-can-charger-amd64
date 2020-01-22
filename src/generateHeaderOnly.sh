#!/bin/sh
# Copyright (C) 2019  Christian Berger
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

WD=$PWD
cd /tmp && rm -fr gen && mkdir gen && cd gen && \
cantools generate_c_source $WD/$1 && \
HEADER_FILE=$(ls *.h)
SOURCE_FILE=$(ls *.c)
cat $SOURCE_FILE | sed -e 's/\(#include\ "\)/\/\/\1/g' > ${SOURCE_FILE}.mod && \
cat $HEADER_FILE | sed -e '/^struct.*{/{:1; /}\;$/!{N; b1;};p };d;' | sed -r ':a; s%(.*)/\*.*\*/%\1%; ta; /\/\*/ !b; N; ba'|sed -e '/^[[:space:]]*$/d'|sed '
/^struct/{
h
d
}
G
s/^\(.*\)\n\(.*\)/\2 \1\:/' | grep -v "{ };" | tr -s " " " "| cut -f2,5 -d" "|sed -e 's/\ /\./g;s/\;//g' > $WD/${1}.map && \
cat $HEADER_FILE | sed -e 's/\(^[^\ \}\#\/\\].*_encode.*\)/inline\ \1/g;s/\(^[^\ \}\#\/\\].*_decode.*\)/inline\ \1/g;s/\(^[^\ \}\#\/\\].*_is_in_range.*\)/inline\ \1/g;s/\(^[^\ \}\#\/\\].*_pack.*\)/inline\ \1/g;s/\(^[^\ \}\#\/\\].*_unpack.*\)/inline\ \1/g' > $HEADER_FILE.mod && cat ${SOURCE_FILE}.mod >> $HEADER_FILE.mod && cat $HEADER_FILE.mod > $WD/${HEADER_FILE}pp && \
cluon-msc --cpp $WD/$2 >> $WD/${HEADER_FILE}pp

