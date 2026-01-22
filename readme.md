# 🕹️ Lena

![](https://stuff.lichendust.com/media/lena.webp)

Lena is a compact, handmade framework for making tiny games with palette graphics. It's software-rendered, cross-platform and provides artistic constraints that challenge your creativity without limiting your game's size and scope.

It comes with batteries-included palette graphics, palette-blending and other drawing effects, loaders and decoders for image and audio assets, a simple audio interface, and built-in text rendering. It compiles and runs on:

- Windows (Native)
- macOS (Native)
- Linux (via SDL3)
- WebAssembly (Native)

The core functionality of Lena is implemented from scratch and the whole code base is designed to be extremely legible and hackable. Lena *only* relies on the libraries that ship with the Odin compiler.

In addition to the documentation in this repository, you can browse all historical (and future) versions of the documentation on [Lena's homepage](https://lichendust.com/lena).

## Library and Structure

### Lena

The `lena` directory contains the actual library, with everything you need for windowing, input, audio, rendering and a host of other utilities. Its `readme` contains the entire documentation for the API, as well as an in-depth overview of the paradigms and idioms of the library.

### WASM

The `wasm` directory provides the resources you need to ship a Lena game in a web browser. The `readme` goes into the specifics of how you'll need to modify and compile your code, and how to use the provided JavaScript and HTML assets to host your game.

## A Learning Tool

Lena has an ulterior motive too: it's a tiny code base with many platforms, implementing all but audio decoding natively. If you're new to 'low-level' systems programming and are interested in more building more advanced applications, Lena might be a perfect learning tool for you.

Lena is the intermediate code base I wish I'd had when I was beginning to program: a powerful library I could still read and understand, architected for a beginner to follow, that also does meaningful work and allows me to have fun making games on top of it, without the underlying engine feeling like an unattainable black box.

Ten years too late for me, I hope it can be this for someone else now.

## Acknowledgements

Lena makes use of —

- [Scientifica](https://git.peppe.rs/fonts/scientifica) by [NerdyPepper](https://oppi.li) as its built-in font.
- [Colordome-32](https://lospec.com/palette-list/colordome-32) by [Polyphrog](https://www.pixilart.com/polyphrog/gallery) as its default colour palette.

Lena was inspired by —

- [Kit](https://github.com/rxi/kit) by [rxi](https://rxi.github.io), a similar exercise in compact framework design.
