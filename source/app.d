import std.getopt : config, defaultGetoptPrinter, getopt, GetOptException;
import std.stdio : writeln;

import vxlimagegen;

int main(string[] args)
{

    string inputFilename;
    string outputFilename;

    try {
        auto optResult = getopt(
            args,
            config.required,
            "input|i", "VXL map file", &inputFilename,
            config.required,
            "output|o", "PNG output file", &outputFilename
        );

        if (optResult.helpWanted) {
            defaultGetoptPrinter("Generate a preview image for a VXL map.", optResult.options);
            return 0;
        }
    } catch (GetOptException ex) {
        writeln("Error: Both input and output must be specified. Use -h for help.");
        return 1;
    }

    drawMap(inputFilename, outputFilename);

    return 0;
}
