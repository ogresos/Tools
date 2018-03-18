/*
 *                                Copyright (C) 2015 by Rafael Santiago
 *
 * This is a free software. You can redistribute it and/or modify under
 * the terms of the GNU General Public License version 2.
 *
 */
#include "udp.h"
#include "memory.h"
#include <string.h>

void parse_udp_dgram(struct udp **hdr, const unsigned char *buf, size_t bsize) {
    struct udp *udp = *hdr;
    size_t p = 0;
    if (udp == NULL || buf == NULL || bsize == 0) {
        return;
    }
    udp->src = ((unsigned short)buf[0] << 8) | buf[1];
    udp->dst = ((unsigned short)buf[2] << 8) | buf[3];
    udp->len = ((unsigned short)buf[4] << 8) | buf[5];
    udp->chsum = ((unsigned short)buf[6] << 8) | buf[7];
    if (bsize > 8) {
        udp->payload_size = bsize - 8;
        udp->payload = (unsigned char *) pig_newseg(udp->payload_size);
        for (p = 0; p < udp->payload_size; p++) {
            udp->payload[p] = buf[8 + p];
        }
    } else {
        udp->payload = NULL;
        udp->payload_size = 0;
    }
}

unsigned char *mk_udp_buffer(const struct udp *hdr, size_t *bsize) {
    unsigned char *retval = NULL;
    size_t p = 0;
    if (hdr == NULL || bsize == NULL) {
        return NULL;
    }
    *bsize = hdr->len;
    retval = (unsigned char *)pig_newseg(*bsize);
    retval[0] = (hdr->src & 0xff00) >> 8;
    retval[1] = hdr->src & 0x00ff;
    retval[2] = (hdr->dst & 0xff00) >> 8;
    retval[3] = hdr->dst & 0x00ff;
    retval[4] = (hdr->len & 0xff00) >> 8;
    retval[5] = hdr->len & 0x00ff;
    retval[6] = (hdr->chsum & 0xff00) >> 8;
    retval[7] = hdr->chsum & 0x00ff;
    for (p = 0; p < hdr->payload_size; p++) {
        retval[8 + p] = hdr->payload[p];
    }
    return retval;
}

unsigned short eval_udp_chsum(const struct udp hdr, const unsigned int src_addr,
                              const unsigned int dst_addr, unsigned short phdr_len) {
    int retval = 0;
    size_t p = 0;
    unsigned char hi = 0, lo = 0;
    retval = (src_addr >> 16) +
             (src_addr & 0x0000ffff) +
             (dst_addr >> 16) +
             (dst_addr & 0x0000ffff) + 0x0011 + phdr_len;
    retval += hdr.src;
    retval += hdr.dst;
    retval += hdr.len;
    retval += hdr.chsum;
    if (hdr.payload_size > 0 && hdr.payload != NULL) {
        p = 0;
        while (p < hdr.payload_size) {
            hi = hdr.payload[p++];
            lo = 0;
            if (p < hdr.payload_size) {
                lo = hdr.payload[p++];
            }
            retval += (((unsigned short)hi << 8) | lo);
        }
    }
    while (retval >> 16) {
        retval = (retval >> 16) + (retval & 0x0000ffff);
    }
    return (unsigned short)(~retval);
}

void *get_udp_payload(const unsigned char *buf, const size_t buf_size, size_t *field_size) {
    struct udp hdr;
    struct udp *phdr = &hdr;
    void *payload = NULL;
    int start_offset = 0;

    if (field_size != NULL) {
        *field_size = 0;
    }

    if (buf == NULL) {
        return NULL;
    }

    //  TODO(Santiago): When added support for ip6, strip off it.
    if ((buf[0] >> 4) != 4) {
        return NULL;
    }

    start_offset = 4 * (buf[0] & 0x0f);

    if ((buf + start_offset) > (buf + buf_size)) {
        return NULL;
    }

    phdr->payload = NULL;
    parse_udp_dgram(&phdr, buf + start_offset, buf_size - start_offset);

    if (field_size != NULL) {
        *field_size = phdr->payload_size;
    }

    if (phdr->payload == NULL) {
        return NULL;
    }

    payload = pig_newseg(phdr->payload_size);
    memcpy(payload, phdr->payload, phdr->payload_size);

    free(phdr->payload);

    return payload;
}
