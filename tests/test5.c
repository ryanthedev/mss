/*
 * Test 5: Call Library Function
 * Actually call macos_sa_create() to create a context
 */

#include <stdio.h>
#include "macos_sa.h"

int main(void)
{
    printf("Test 5: Creating context...\n");

    macos_sa_context *ctx = macos_sa_create(NULL);
    if (ctx) {
        printf("  Context created successfully: %p\n", (void *)ctx);
        printf("  Socket path: %s\n", macos_sa_get_socket_path(ctx));
        macos_sa_destroy(ctx);
        printf("Test 5: SUCCESS\n");
    } else {
        printf("  Failed to create context\n");
        printf("Test 5: FAILED\n");
        return 1;
    }

    return 0;
}
