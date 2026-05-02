#include <ruby.h>
#include "translation_mac.h"

static VALUE rb_translation_mac_perform(VALUE self, VALUE input) {
    const char *c_input = StringValueCStr(input);
    char *result = translation_mac_perform(c_input);
    if (result == NULL) {
        return rb_utf8_str_new_cstr("");
    }
    VALUE rb_result = rb_utf8_str_new_cstr(result);
    translation_mac_free(result);
    return rb_result;
}

void Init_translation_mac(void) {
    VALUE module = rb_define_module("TranslationMac");
    rb_define_singleton_method(module, "perform", rb_translation_mac_perform, 1);
}
