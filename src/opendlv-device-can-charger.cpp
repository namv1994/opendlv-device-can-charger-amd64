/*
 * Copyright (C) 2019  Christian Berger
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include "cluon-complete.hpp"
#include "opendlv-standard-message-set.hpp"
#include "chargergw.hpp"

#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/select.h>

#ifdef __linux__
    #include <linux/if.h>
    #include <linux/can.h>
#endif

#include <unistd.h>

#include <cerrno>
#include <cstdint>
#include <cstring>

#include <iostream>
#include <iomanip>
#include <string>
#include <sstream>

int32_t main(int32_t argc, char **argv) {
    int32_t retCode{1};
    auto commandlineArguments = cluon::getCommandlineArguments(argc, argv);
    if ( (0 == commandlineArguments.count("cid")) ) {
        std::cerr << argv[0] << " translates messages from CAN to ODVD messages." << std::endl;
        std::cerr << "Usage:   " << argv[0] << " --cid=<OD4 session> [--id=ID] --can=<name of the CAN device> [--enablethrottle] [--enablebrake] [--enablesteering] [--verbose]" << std::endl;
        std::cerr << "         --cid:    CID of the OD4Session to send and receive messages" << std::endl;
        std::cerr << "         --id:     ID to use as senderStamp for sending" << std::endl;
        std::cerr << "Example: " << argv[0] << " --cid=111 --can=can0 --verbose" << std::endl;
    }
    else {
        const std::string CANDEVICE{commandlineArguments["can"]};
        const uint32_t ID{(commandlineArguments["id"].size() != 0) ? static_cast<uint32_t>(std::stoi(commandlineArguments["id"])) : 0};
        const bool VERBOSE{commandlineArguments.count("verbose") != 0};

        // Interface to a running OpenDaVINCI session; here, you can send and receive messages.
        cluon::OD4Session od4{static_cast<uint16_t>(std::stoi(commandlineArguments["cid"]))};

        // Delegate to convert incoming CAN frames into ODVD messages that are broadcast into the OD4Session.
        opendlv::proxy::Charger msg;
        auto decode = [&od4, VERBOSE, ID, &msg](cluon::data::TimeStamp ts, uint16_t canFrameID, uint8_t *src, uint8_t len) {
            if ( (nullptr == src) || (0 == len) )  {
                if(VERBOSE)
                    std::cout << "src = " << src << ", len =  " << len << std::endl;
                return;
            }
            
            if (CHARGERGW_CHARGER_FRAME_ID == canFrameID) {
                chargergw_charger_t tmp;
                if (0 == chargergw_charger_unpack(&tmp, src, len)) {
                    opendlv::proxy::Charger msg;
                    msg.voltage2(chargergw_charger_voltage2_decode(tmp.voltage2));
                    msg.current2(chargergw_charger_current2_decode(tmp.current2));

                    if (VERBOSE) {
                        std::stringstream sstr;
                        msg.accept([](uint32_t, const std::string &, const std::string &) {},
                           [&sstr](uint32_t, std::string &&, std::string &&n, auto v) { sstr << n << " = " << v << '\n'; },
                           []() {});
                        std::cout << sstr.str() << std::endl;
                    }

                    od4.send(msg, ts, ID);
                }
            }
        };

#ifdef __linux__
        struct sockaddr_can address;
#endif
        int socketCAN;

        std::cerr << "[opendlv-device-can-charger] Opening " << CANDEVICE << "... ";
#ifdef __linux__
        // Create socket for SocketCAN.
        socketCAN = socket(PF_CAN, SOCK_RAW, CAN_RAW);
        if (socketCAN < 0) {
            std::cerr << "failed." << std::endl;

            std::cerr << "[opendlv-device-can-charger] Error while creating socket: " << strerror(errno) << std::endl;
        }

        // Try opening the given CAN device node.
        struct ifreq ifr;
        memset(&ifr, 0, sizeof(ifr));
        strcpy(ifr.ifr_name, CANDEVICE.c_str());
        if (0 != ioctl(socketCAN, SIOCGIFINDEX, &ifr)) {
            std::cerr << "failed." << std::endl;

            std::cerr << "[opendlv-device-can-charger] Error while getting index for " << CANDEVICE << ": " << strerror(errno) << std::endl;
            return retCode;
        }

        // Setup address and port.
        memset(&address, 0, sizeof(address));
        address.can_family = AF_CAN;
        address.can_ifindex = ifr.ifr_ifindex;

        if (bind(socketCAN, reinterpret_cast<struct sockaddr *>(&address), sizeof(address)) < 0) {
            std::cerr << "failed." << std::endl;

            std::cerr << "[opendlv-device-can-charger] Error while binding socket: " << strerror(errno) << std::endl;
            return retCode;
        }
        std::cerr << "done." << std::endl;
#else
        std::cerr << "failed (SocketCAN not available on this platform). " << std::endl;
        return retCode;
#endif

        struct can_frame frame;
        fd_set rfds;
        struct timeval timeout;
        struct timeval socketTimeStamp;
        int32_t nbytes = 0;

        while (od4.isRunning() && socketCAN > -1) {
#ifdef __linux__
            timeout.tv_sec = 1;
            timeout.tv_usec = 0;

            FD_ZERO(&rfds);
            FD_SET(socketCAN, &rfds);

            select(socketCAN + 1, &rfds, NULL, NULL, &timeout);
            if (FD_ISSET(socketCAN, &rfds)) {
                nbytes = read(socketCAN, &frame, sizeof(struct can_frame));
                if ( (nbytes > 0) && (nbytes == sizeof(struct can_frame)) ) {
                    // Get receiving time stamp.
                    if (0 != ioctl(socketCAN, SIOCGSTAMP, &socketTimeStamp)) {
                        // In case the ioctl failed, use traditional vsariant.
                        cluon::data::TimeStamp now{cluon::time::now()};
                        socketTimeStamp.tv_sec = now.seconds();
                        socketTimeStamp.tv_usec = now.microseconds();
                    }
                    cluon::data::TimeStamp sampleTimeStamp;
                    sampleTimeStamp.seconds(socketTimeStamp.tv_sec)
                                   .microseconds(socketTimeStamp.tv_usec);
                    decode(sampleTimeStamp, frame.can_id, frame.data, frame.can_dlc);
                }
            }
#endif
        }

        std::clog << "[opendlv-device-can-charger] Closing " << CANDEVICE << "... ";
        if (socketCAN > -1) {
            close(socketCAN);
        }
        std::clog << "done." << std::endl;

        retCode = 0;
    }
    return retCode;
}

