#include <iostream>
#include <fstream>
#include <cstdint>
#include <vector>
#include <algorithm>
#include <chrono>
#include <thread>
#include <mutex>
#include <boost/asio.hpp>
#include <boost/asio/steady_timer.hpp>
#include <boost/asio/high_resolution_timer.hpp>
#include <boost/test/execution_monitor.hpp>
#include <boost/program_options.hpp>

#include <linux/if_packet.h>
#include <net/if.h>

class benchmark
{
    boost::asio::io_service& m_io_service;
    boost::asio::io_service& m_timer_io_service;
    boost::program_options::variables_map m_options;
    boost::asio::generic::raw_protocol::socket m_socket;

    std::ofstream m_stat_file;

    bool m_statistics_started = false;
    std::uint32_t m_send_sequence = 1;
    std::uint32_t m_recv_sequence = 0;
    std::vector<std::uint8_t> m_recv_data = std::vector<std::uint8_t> (1600);
    boost::asio::generic::raw_protocol::endpoint m_recv_endpoint, m_send_endpoint;
    std::vector<std::uint8_t> m_data_header;
    // Map of sequence number to data
    std::map<std::uint32_t, std::shared_ptr<std::vector<std::uint8_t>>> m_packet_data_sent;

    boost::asio::steady_timer m_end_timer;
    boost::asio::high_resolution_timer m_statistic_timer;

    bool m_check_content;
    bool m_verbose;
    bool m_recv_only;

    unsigned int m_stop_at_sequence = 0;

    std::mutex m_statistics_mutex;
    unsigned int m_recv_bytes_second = 0;
    unsigned int m_recv_packets_second = 0;
    unsigned int m_send_bytes_second = 0;
    unsigned int m_send_packets_second = 0;

    unsigned int m_missed_sequence = 0;
    unsigned int m_recv_malformed = 0;

public:

    benchmark(boost::asio::io_service & io_service, boost::asio::io_service & timer_io_service, boost::program_options::variables_map const & options)
    : m_io_service(io_service), m_timer_io_service(timer_io_service), m_options(options), m_socket(io_service, boost::asio::generic::raw_protocol(AF_PACKET, htons(0xFFFF))), m_end_timer(timer_io_service), m_statistic_timer(timer_io_service)
    {
        m_check_content = !(m_options["no-content-check"].as<bool>());
        m_verbose = m_options["verbose"].as<bool>();
        m_recv_only = m_options["receive-only"].as<bool>();
        if (m_options.count("limit")) {
            m_stop_at_sequence = m_options["limit"].as<unsigned int>();
        }
        if (m_options.count("time-limit")) {
            m_end_timer.expires_from_now(std::chrono::seconds(m_options["time-limit"].as<unsigned int>()));
            m_end_timer.async_wait([this] (boost::system::error_code ec)
            {
                std::cout << "Time limit reached, exiting" << std::endl;
                m_stat_file.close();
                        std::exit(0);
            });
        }
        if (m_options.count("stat-file")) {
            m_stat_file.open(m_options["stat-file"].as<std::string>());
            m_stat_file << "bps_rx,bps_tx" << std::endl;
        }

        struct sockaddr_ll send_addr;
        std::memset(&send_addr, 0, sizeof(send_addr));
        send_addr.sll_ifindex = if_nametoindex(m_options["interface"].as<std::string>().c_str());
        if (send_addr.sll_ifindex == 0) {
            throw boost::system::system_error(errno, boost::system::posix_category);
        }
        m_send_endpoint = boost::asio::generic::raw_protocol::endpoint(&send_addr, sizeof(send_addr));
        int setopt_value = 1;
        /*if (setsockopt(m_socket.native_handle(), SOL_PACKET, PACKET_QDISC_BYPASS, &setopt_value, sizeof(setopt_value)) != 0) {
        throw std::runtime_error("setsockopt failed");
        }*/
        setopt_value = 9524288;
        if (setsockopt(m_socket.native_handle(), SOL_SOCKET, SO_RCVBUFFORCE, &setopt_value, sizeof(setopt_value)) != 0) {
            throw std::runtime_error("setsockopt failed");
        }
        if (setsockopt(m_socket.native_handle(), SOL_SOCKET, SO_SNDBUFFORCE, &setopt_value, sizeof(setopt_value)) != 0) {
            throw std::runtime_error("setsockopt failed");
        }

        m_data_header = {
            // destination address
            0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
            // source address
            0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
            // ethertype
            0xFF, 0xFF,
        };

        start_read();
        if (!m_recv_only) {
            // The TX buffer can only be filled up to a certain amount
            // Additional packets will just end up getting dropped!
            for (int prefill = 0; prefill < m_options["prefill-count"].as<unsigned int>(); prefill++) {
                start_send();
            }
        }
        start_statistic_report();
    }

    void start_read()
    {
        m_socket.async_receive_from(boost::asio::buffer(m_recv_data), m_recv_endpoint, [this](boost::system::error_code ec, std::size_t length)
        {
            if (ec) {
                throw boost::system::system_error(ec);
            }
            const int DIRECTION_POS = 14;
            const int RECV_SEQUENCE_POS = 15;

            if (!m_recv_only) {
                        std::uint32_t recv_sequence = (m_recv_data[RECV_SEQUENCE_POS] << 24) + (m_recv_data[RECV_SEQUENCE_POS + 1] << 16) + (m_recv_data[RECV_SEQUENCE_POS + 2] << 8) + m_recv_data[RECV_SEQUENCE_POS + 3];
                        auto sent_data = m_packet_data_sent.at(recv_sequence);
                        // Free memory in buffer
                        m_packet_data_sent.erase(recv_sequence);

                        // Check received packet
                        bool malformed = false;
                if (sent_data->size() != length) {
                    std::cout << "Size mismatch: Sequence number " << recv_sequence << " had " << sent_data->size() << " bytes sent, " << length << " received" << std::endl;
                            malformed = true;
                }
                if (!malformed && !std::equal(m_data_header.begin(), m_data_header.end(), m_recv_data.begin())/* || m_recv_data[DIRECTION_POS] != 0x01*/) {
                    std::cout << "Header mismatch" << std::endl;
                            malformed = true;
                }
                if (!malformed && m_check_content && 0 != std::memcmp(m_recv_data.data(), sent_data->data(), length)) {
                    std::cout << "Frame data mismatch" << std::endl;
                            malformed = true;
                }
                if (malformed) {
                    if (m_verbose) {
                        std::cout << "Malformed packet: " << std::endl;
                                std::cout << std::hex;
                        for (int i = 0; i < length; i++) {
                            std::cout << static_cast<unsigned short> (m_recv_data[i]) << " ";
                        }
                        std::cout << std::dec << std::endl;
                    }
                    m_recv_malformed++;
                }

                if (m_verbose) {
                    std::cout << "Received " << recv_sequence << " length " << length << std::endl;
                }

                if (recv_sequence != m_recv_sequence + 1) {
                    auto missing_count = recv_sequence - m_recv_sequence - 1U;
                            std::cout << "Missed " << missing_count << " packet(s) (sequence numbers " << (m_recv_sequence + 1U) << " to " << (recv_sequence - 1U) << ")" << std::endl;
                            m_missed_sequence += missing_count;
                }
                m_recv_sequence = recv_sequence;
            }
            {
                std::lock_guard<std::mutex> lock(m_statistics_mutex);
                m_recv_packets_second++;
                m_recv_bytes_second += (length - 14);
            }
                    //std::cout << "Recvd size " << length << std::endl;
                    start_read();
            if (!m_recv_only) {
                    start_send();
            }
        }
        );
    }

    void start_send()
    {
        // Data needs to stay valid until the send handler is invoked
        auto send_data = std::make_shared<std::vector < std::uint8_t >> (m_data_header);

        send_data->insert(send_data->end(),
        {
            // direction flag
            0x00,
            // sequence number
            static_cast<std::uint8_t> (m_send_sequence >> 24), static_cast<std::uint8_t> (m_send_sequence >> 16), static_cast<std::uint8_t> (m_send_sequence >> 8), static_cast<std::uint8_t> (m_send_sequence)
        });
        unsigned int start = send_data->size();
        send_data->resize(1514);
        std::uint8_t c = m_send_sequence ^ (m_send_sequence >> 8) ^ (m_send_sequence >> 16);
        for (unsigned int i = start; i < 1500 - 1 - 4; i++) {
            (*send_data)[i] = i ^ c;
        }
        //send_data->insert(send_data->end(), 1500 - 1 - 4, 0x23);
        m_packet_data_sent.emplace(m_send_sequence, send_data);
        m_send_sequence++;
        m_socket.async_send_to(boost::asio::buffer(*send_data), m_send_endpoint, [this, send_data](boost::system::error_code ec, std::size_t sent)
        {
            if (m_verbose) {
                std::cout << "Sent " << m_send_sequence << std::endl;
            }
            if (ec) {
                throw boost::system::system_error(ec);
            }
            if (m_stop_at_sequence != 0 && m_stop_at_sequence == m_send_sequence) {
                std::cout << "Sequence number limit reached, exiting" << std::endl;
                std::exit(2);
            }
            std::lock_guard<std::mutex> lock(m_statistics_mutex);
            m_send_packets_second++;
            m_send_bytes_second += (sent - 14);
                    //start_send();
        });
    }

    void start_statistic_report()
    {
        bool skip_write = false;
        if (m_statistics_started) {
            // Do not use expires_from_now()! Inaccuracies would quickly build up.
            m_statistic_timer.expires_at(m_statistic_timer.expires_at() + std::chrono::seconds(1));
        } else {
            m_statistic_timer.expires_from_now(std::chrono::seconds(1));
            m_statistics_started = true;
            // Skip first data row: Accumulated cruft from the socket buffer is read out first
            skip_write = true;
        }
        m_statistic_timer.async_wait([this, skip_write] (boost::system::error_code ec)
        {
            if (ec) {
                throw boost::system::system_error(ec);
            }
            std::cout << "Statistics: RX " << m_recv_packets_second << " packets/s " << (m_recv_bytes_second * 8) << " bits/s  TX " << m_send_packets_second << " packets/s " << (m_send_bytes_second * 8) << " bits/s" << std::endl;
            std::cout << "Cumulative malformed packets: " << m_recv_malformed << ", cumulative missing sequence numbers: " << m_missed_sequence << std::endl;
            {
                std::lock_guard<std::mutex> lock(m_statistics_mutex);
                if (m_stat_file.is_open() && !skip_write) {
                    m_stat_file << (m_recv_bytes_second * 8) << "," << (m_send_bytes_second * 8) << std::endl;
                }
                m_send_packets_second = m_send_bytes_second = m_recv_bytes_second = m_recv_packets_second = 0;
            }
            start_statistic_report();
        });
    }

};

int main(int argc, char* argv[])
{
    try {
        boost::program_options::options_description opts("Options");
        opts.add_options()
                ("no-content-check,c", boost::program_options::bool_switch(), "Do not compare packet contents")
                ("interface,i", boost::program_options::value<std::string>(), "Interface to run the benchmark on")
                ("verbose,v", boost::program_options::bool_switch(), "Print verbose output")
                ("limit,l", boost::program_options::value<unsigned int>(), "Stop after specified sequence number sent")
                ("time-limit,t", boost::program_options::value<unsigned int>(), "Stop after specified number of seconds")
                ("prefill-count,p", boost::program_options::value<unsigned int>()->default_value(40), "Number of maximum packets in send buffer")
                ("stat-file,o", boost::program_options::value<std::string>(), "File to write statistical information to")
		("receive-only,r", boost::program_options::bool_switch(), "Do not send any packets and do not verify received data, only print statistical information");
        ;

        boost::program_options::variables_map options;

        boost::program_options::store(boost::program_options::parse_command_line(argc, argv, opts), options);
        if (options.count("interface") == 0) {
            std::cerr << opts << std::endl;
            return 1;
        }

        boost::asio::io_service io_service, timer_io_service;
        benchmark b(io_service, timer_io_service, options);
        std::thread timer_thread([&timer_io_service] () {
            timer_io_service.run();
        });
        io_service.run();
        return 0;
    } catch (std::exception& e) {
        std::cerr << "Critical exception: " << e.what() << std::endl;
        return 1;
    }
}
