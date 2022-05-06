set_languages("cxx20")
add_rules("mode.debug", "mode.release")

add_cxflags("/bigobj", "/MP")

target("test")
    set_kind("shared")
    add_files("*.cpp")
    set_filename("radioExt.asi")