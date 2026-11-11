// Makes the release probe byte-reproducible under MSVC link.exe: without
// /Brepro the PE header carries the link time, so identical sources hash
// differently on every build.

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    if std::env::var("CARGO_CFG_TARGET_ENV").as_deref() == Ok("msvc") {
        println!("cargo:rustc-link-arg-bins=/Brepro");
    }
}
