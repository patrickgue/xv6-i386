#include <kernel/types.h>
#include <kernel/stat.h>
#include <kernel/user.h>

int
main(int argc, char *argv[])
{
  int i;

  for(i = 1; i < argc; i++)
    printf(1, "%s%s", argv[i], i+1 < argc ? " " : "\n");
  exit();
}
