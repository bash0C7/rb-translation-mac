#include <ruby.h>
#include "TranslationMac-Swift.h"

static VALUE rb_translation_mac_supported_languages(VALUE self) {
    char *result = translation_mac_supported_languages();
    if (result == NULL) return rb_ary_new();
    VALUE str = rb_utf8_str_new_cstr(result);
    translation_mac_free(result);
    if (RSTRING_LEN(str) == 0) return rb_ary_new();
    return rb_str_split(str, "\n");
}

static VALUE rb_translation_mac_status(int argc, VALUE *argv, VALUE self) {
    VALUE opts;
    rb_scan_args(argc, argv, "0:", &opts);
    if (NIL_P(opts)) rb_raise(rb_eArgError, "expected keyword args from: and to:");
    VALUE from = rb_hash_aref(opts, ID2SYM(rb_intern("from")));
    VALUE to   = rb_hash_aref(opts, ID2SYM(rb_intern("to")));
    if (NIL_P(from) || NIL_P(to)) rb_raise(rb_eArgError, "from: and to: are required");

    const char *c_from = StringValueCStr(from);
    const char *c_to   = StringValueCStr(to);
    char *result = translation_mac_status(c_from, c_to);
    if (result == NULL) return ID2SYM(rb_intern("unsupported"));
    VALUE sym = ID2SYM(rb_intern(result));
    translation_mac_free(result);
    return sym;
}

void Init_translation_mac(void) {
    VALUE module = rb_define_module("TranslationMac");
    rb_define_singleton_method(module, "supported_languages", rb_translation_mac_supported_languages, 0);
    rb_define_singleton_method(module, "status", rb_translation_mac_status, -1);
}
