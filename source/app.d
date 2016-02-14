import std.getopt : config, defaultGetoptPrinter, getopt, GetOptException;
import std.stdio : writeln;

import vxlimagegen;

int main(string[] args)
{

    string inputFilename;
    string outputFilename;
    Colour backgroundColour;
    bool transparentBackground = false;

    bool errored = false;

    void backgroundColourHandler(string option, string value) {
        try {
            backgroundColour = parseColourString(value);
        } catch (InvalidColourException ex) {
            writeln("Error: ", ex.msg);
            errored = true;
        }
    }

    try {
        auto optResult = getopt(
            args,
            config.required,
            "input|in|i", "VXL map file", &inputFilename,
            config.required,
            "output|out|o", "PNG output file", &outputFilename,
            "background|b", "background colour", &backgroundColourHandler,
            "transparent|t", "transparent background", &transparentBackground,
        );

        if (optResult.helpWanted) {
            defaultGetoptPrinter("Generate a preview image for a VXL map.", optResult.options);
            return 0;
        }
    } catch (GetOptException ex) {
        debug {
            writeln(ex.msg);
        }
        writeln("Error: Both input and output must be specified. Use -h for help.");
        return 1;
    }

    if (errored) return 1;

    if (transparentBackground) {
        backgroundColour.a = 0;
    }

    try {
        drawMap(inputFilename, outputFilename, backgroundColour);
    } catch (InvalidMapException ex) {
        writeln("Error while drawing map: ", ex.msg);
        return 1;
    }

    return 0;
}
