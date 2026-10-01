#include "my_application.h"
#include "shoshot_native.h"

int main(int argc, char** argv) {
  shoshot_register_host_app_id(APPLICATION_ID);
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
