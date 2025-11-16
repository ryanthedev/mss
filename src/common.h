#ifndef SA_COMMON_H
#define SA_COMMON_H

#define OSAX_VERSION                "2.1.23"

#define OSAX_ATTRIB_DOCK_SPACES     0x01
#define OSAX_ATTRIB_DPPM            0x02
#define OSAX_ATTRIB_ADD_SPACE       0x04
#define OSAX_ATTRIB_REM_SPACE       0x08
#define OSAX_ATTRIB_MOV_SPACE       0x10
#define OSAX_ATTRIB_SET_WINDOW      0x20
#define OSAX_ATTRIB_ANIM_TIME       0x40

#define OSAX_ATTRIB_ALL             (OSAX_ATTRIB_DOCK_SPACES | \
                                     OSAX_ATTRIB_DPPM | \
                                     OSAX_ATTRIB_ADD_SPACE | \
                                     OSAX_ATTRIB_REM_SPACE | \
                                     OSAX_ATTRIB_MOV_SPACE | \
                                     OSAX_ATTRIB_SET_WINDOW | \
                                     OSAX_ATTRIB_ANIM_TIME)

enum sa_opcode
{
    SA_OPCODE_HANDSHAKE             = 0x01,
    SA_OPCODE_SPACE_FOCUS           = 0x02,
    SA_OPCODE_SPACE_CREATE          = 0x03,
    SA_OPCODE_SPACE_DESTROY         = 0x04,
    SA_OPCODE_SPACE_MOVE            = 0x05,
    SA_OPCODE_WINDOW_MOVE           = 0x06,
    SA_OPCODE_WINDOW_OPACITY        = 0x07,
    SA_OPCODE_WINDOW_OPACITY_FADE   = 0x08,
    SA_OPCODE_WINDOW_LAYER          = 0x09,
    SA_OPCODE_WINDOW_STICKY         = 0x0A,
    SA_OPCODE_WINDOW_SHADOW         = 0x0B,
    SA_OPCODE_WINDOW_FOCUS          = 0x0C,
    SA_OPCODE_WINDOW_SCALE          = 0x0D,
    SA_OPCODE_WINDOW_SWAP_PROXY_IN  = 0x0E,
    SA_OPCODE_WINDOW_SWAP_PROXY_OUT = 0x0F,
    SA_OPCODE_WINDOW_ORDER          = 0x10,
    SA_OPCODE_WINDOW_ORDER_IN       = 0x11,
    SA_OPCODE_WINDOW_LIST_TO_SPACE  = 0x12,
    SA_OPCODE_WINDOW_TO_SPACE       = 0x13,
    // Window resize operations
    SA_OPCODE_WINDOW_RESIZE         = 0x14,
    SA_OPCODE_WINDOW_SET_FRAME      = 0x15,
    // Window query operations
    SA_OPCODE_WINDOW_GET_OPACITY    = 0x16,
    SA_OPCODE_WINDOW_GET_FRAME      = 0x17,
    SA_OPCODE_WINDOW_IS_STICKY      = 0x18,
    SA_OPCODE_WINDOW_GET_LAYER      = 0x19,
    // Window minimize operations
    SA_OPCODE_WINDOW_MINIMIZE       = 0x1A,
    SA_OPCODE_WINDOW_UNMINIMIZE     = 0x1B,
    SA_OPCODE_WINDOW_IS_MINIMIZED   = 0x1C,
    // Display queries
    SA_OPCODE_DISPLAY_GET_COUNT     = 0x1D,
    SA_OPCODE_DISPLAY_GET_LIST      = 0x1E,
};

#endif
