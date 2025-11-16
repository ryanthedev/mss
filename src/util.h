#ifndef MACOS_SA_UTIL_H
#define MACOS_SA_UTIL_H

#include <stdbool.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <string.h>
#include <stdio.h>

// Socket utilities for communicating with the SA
static inline bool socket_open(int *sockfd)
{
    *sockfd = socket(AF_UNIX, SOCK_STREAM, 0);
    return *sockfd != -1;
}

static inline bool socket_connect(int sockfd, char *socket_path)
{
    struct sockaddr_un socket_address;
    socket_address.sun_family = AF_UNIX;

    snprintf(socket_address.sun_path, sizeof(socket_address.sun_path), "%s", socket_path);
    return connect(sockfd, (struct sockaddr *) &socket_address, sizeof(socket_address)) != -1;
}

static inline void socket_close(int sockfd)
{
    shutdown(sockfd, SHUT_RDWR);
    close(sockfd);
}

// System utilities
static inline bool is_root(void)
{
    return getuid() == 0 || geteuid() == 0;
}

// String utilities
static inline bool string_equals(const char *a, const char *b)
{
    return a && b && strcmp(a, b) == 0;
}

#endif
