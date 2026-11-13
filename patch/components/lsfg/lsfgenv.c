/* Loaded just before the lsfg-metal shim. NotProton passes only a few environment
 * variable prefixes into the game, so set what the shim needs here, inside the game:
 * LSFGM_METAL turns on its Metal present hooks, and LSFGM_GENERATOR_MOLTENVK points
 * frame generation at a MoltenVK new enough for it (CrossOver's 1.2.10 renders black). */
#include <dlfcn.h>
#include <libgen.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

__attribute__((constructor)) static void lsfgenv_init(void)
{
    Dl_info info;
    char self[PATH_MAX], gen[PATH_MAX];

    setenv("LSFGM_METAL", "1", 0);
    if (!dladdr((void *)lsfgenv_init, &info) || !info.dli_fname) return;
    strlcpy(self, info.dli_fname, sizeof(self));
    snprintf(gen, sizeof(gen), "%s/libMoltenVK.generator.dylib", dirname(self));
    if (!access(gen, R_OK)) setenv("LSFGM_GENERATOR_MOLTENVK", gen, 0);
}
