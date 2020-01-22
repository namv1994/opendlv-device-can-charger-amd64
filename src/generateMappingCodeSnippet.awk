#!/usr/bin/gawk -f
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

BEGIN {
    FS="_t\\.";
}

# Build map of entries:
# Key: struct name, Values: mappings from struct's field to ODVD signal.
{
    mapOfAllStructs[$1] = mapOfAllStructs[$1] "," $2;
}

END {
    # Generate encoder.
    print "inline int encode(uint8_t *dst, uint8_t len);"
    print "int encode(uint8_t *dst, uint8_t len) {"
    print "    if ( (nullptr == dst) || (0 == len) ) return 0;"
    print "    // TODO: Provide logic to check what messages to actually encode; the code in the"
    print "    //       following is mainly template code for illustration."
    print " "
    for (structName in mapOfAllStructs) {
    print "    // Message to encode: " toupper(structName) "_FRAME_ID"
    print "    {"
    print "        "structName "_t tmp;"
    print "        memset(&tmp, 0, sizeof(tmp));"
        split(substr(mapOfAllStructs[structName],2), fieldsInStruct, ",")
        ODVDMessage = ""
        foundMapping = 0
        for (field in fieldsInStruct) {
            # Extract mapping.
            split(fieldsInStruct[field], mapping, ":")
            if ("" == ODVDMessage) {
                # Create instance from ODVD message.
                n = split(mapping[2], tokens, ".")
                for (i = 1; i < n-1; i++) {
                    ODVDMessage = ODVDMessage tokens[i] "::"
                }
                ODVDMessage = ODVDMessage tokens[n-1]
                foundMapping = ("" != ODVDMessage)
                if (foundMapping) {
                    print "        // The following msg would have to be passed to this encoder externally."
                    print "        " ODVDMessage " msg;"
                }
            }
            if (foundMapping) {
                n = split(mapping[2], tokens, ".")
                ODVDMessageAttribute = tokens[n]
                if ("" != ODVDMessageAttribute) {
                    print "        tmp." mapping[1] " = " structName "_" mapping[1] "_encode(msg." ODVDMessageAttribute "());"
                }
            }
        }
        if (foundMapping) {
            print "        // The following statement packs the encoded values into a CAN frame."
            print "        int size = " structName "_pack(dst, &tmp, len);"
            print "        return size;"
        }
        else {
            print "        (void)tmp;"
            print "        // No mapping defined for " structName
        }
    print "    }"
    }
    print "}"


    # Generate decoder.
    print "inline void decode(uint16_t canFrameID, uint8_t *src, uint8_t len);"
    print "void decode(uint16_t canFrameID, uint8_t *src, uint8_t len) {"
    print "    if ( (nullptr == src) || (0 == len) ) return;"
    structCounter = 0
    for (structName in mapOfAllStructs) {
    if (0 == structCounter) {
    print "    if (" toupper(structName) "_FRAME_ID == canFrameID) {"
    }
    else {
    print "    else if (" toupper(structName) "_FRAME_ID == canFrameID) {"
    }
    print "        "structName "_t tmp;"
    print "        if (0 == " structName "_unpack(&tmp, src, len)) {"
        split(substr(mapOfAllStructs[structName],2), fieldsInStruct, ",")
        ODVDMessage = ""
        foundMapping = 0
        for (field in fieldsInStruct) {
            # Extract mapping.
            split(fieldsInStruct[field], mapping, ":")
            if ("" == ODVDMessage) {
                # Create instance from ODVD message.
                n = split(mapping[2], tokens, ".")
                for (i = 1; i < n-1; i++) {
                    ODVDMessage = ODVDMessage tokens[i] "::"
                }
                ODVDMessage = ODVDMessage tokens[n-1]
                foundMapping = ("" != ODVDMessage)
                if (foundMapping) {
                    print "            " ODVDMessage " msg;"
                }
            }
            if (foundMapping) {
                n = split(mapping[2], tokens, ".")
                ODVDMessageAttribute = tokens[n]
                if ("" != ODVDMessageAttribute) {
                    print "            msg." ODVDMessageAttribute "(" structName "_" mapping[1] "_decode(" "tmp." mapping[1] "));"
                }
            }
        }
        if (foundMapping) {
            print "            // The following block is automatically added to demonstrate how to display the received values."
            print "            {"
            print "                std::stringstream sstr;"
            print "                msg.accept([](uint32_t, const std::string &, const std::string &) {},"
            print "                           [&sstr](uint32_t, std::string &&, std::string &&n, auto v) { sstr << n << \" = \" << v << '\\n'; },"
            print "                           []() {});"
            print "                std::cout << sstr.str() << std::endl;"
            print "            }"
        }
        else {
            print "            // No mapping defined for " structName
        }
    print "        }"
    print "    }"
    structCounter++
    }
    print "}"
}

