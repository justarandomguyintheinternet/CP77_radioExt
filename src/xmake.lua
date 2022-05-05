set_languages("cxx20")
add_rules("mode.debug", "mode.release")

add_cxflags("/bigobj", "/MP")
add_defines("UNICODE")

target("test")
    add_defines("WIN32_LEAN_AND_MEAN", "NOMINMAX", "WINVER=0x0601")
    set_kind("shared")
    add_files("src/*.cpp")
    set_filename("radioExt.asi")
    add_syslinks("User32", "Version")