/* Umbrella header for translate-c. The single place SDL's compile-time
   options are set, so the translation and the linked library cannot
   disagree about what the API looks like. */

/* SDL_main.h rewrites `main` behind the caller's back. Zig has its own entry
   point, so the raw layer must never see that macro. */
#define SDL_MAIN_HANDLED

#include <SDL3/SDL.h>

#ifdef SDL3_ZIG_VULKAN
#include <SDL3/SDL_vulkan.h>
#endif
