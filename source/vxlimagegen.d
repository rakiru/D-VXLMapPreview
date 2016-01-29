module vxlimagegen;

// TODO: Explicit/selective imports, as soon as I figure out why "private import std.uni : toLower" exports toLower publically...
// Oh, turns out it's an ancient bug that has yet to be fixed. That sure makes me want to invest in learning the language... <_<
// https://issues.dlang.org/show_bug.cgi?id=314
import std.algorithm.searching;
import std.file;
import std.format;
import std.stdio;
import std.uni;

import dlib.image;
import dlib.image.io.png;

private const string ICEMAP_HEADER = "IceMap\x1A\x01";
private const string ICEMAP_TAG_MAP_DATA = "MapData";
private const string ICEMAP_TERMINATOR = "       ";

private struct Colour {
    ubyte b;
    ubyte g;
    ubyte r;
}

// TODO: Check if this is how I should be doing thing. Some website somewhere said this was how it was done at some point
// TODO: Perhaps this is a place for a mixin? Seems like a lot of boilerplate for creating an Exception type...
// Obviously a mixin would be useless for one exception here, but you know, future projects and such.
class InvalidMapException : Exception {
    public {
        @safe pure nothrow this(string message, string file=__FILE__, size_t line=__LINE__, Throwable next=null) {
            super(message, file, line, next);
        }
        @safe pure nothrow this(string message, Throwable next, string file=__FILE__, size_t line=__LINE__) {
            super(message, file, line, next);
        }
    }
}

SuperImage generatePreview(ubyte[] data, uint xLength, uint yLength, uint zLength) {

    uint dataPointer = 0;
    uint imgWidth = (xLength + zLength) * 2;
    uint imgHeight = (xLength + zLength) + (yLength * 2);

    SuperImage img = new ImageRGB8(imgWidth, imgHeight);
    // We have to operate on the raw data because the setPixel mathod is private,
    // and the index operator only works on floats. <_<
    auto imgData = img.data;
    auto pixelSize = img.pixelSize;

    Colour[] colours;
    colours.length = yLength;
    uint colourOffset = 0;

    Colour getColour() {
        Colour colour = Colour(
            data[dataPointer++],
            data[dataPointer++],
            data[dataPointer++]
        );
        dataPointer++;  // "Light"
        return colour;
    }

    void drawBlock(uint x, uint y, uint z, Colour colour) {
        uint rx = (z - x) * 2 + (imgWidth / 2);
        uint ry = x + z + (y * 2);
        for (int i = 0; i < 2; i++) {
            uint ii = (((ry + i) * imgWidth) + rx) * pixelSize;
            for (int j = 0; j < 2 * pixelSize; j += pixelSize) {
                imgData[ii + j] = colour.r;
                imgData[ii + j + 1] = colour.g;
                imgData[ii + j + 2] = colour.b;
            }
        }
    }

    for (int x = 0; x < zLength; x++) {
        for (int z = 0; z < xLength; z++) {

            ubyte next;
            ubyte s;
            ubyte e;
            ubyte air_start;
            Colour lastColour = {0, 0, 0};

            // Loop through the data until we reach the end of the pillar
            while (true) {

                // Read control entity
                next = data[dataPointer++];  // Distance to next control block, 0 if no more
                s = data[dataPointer++];  // Start of floor colour run
                e = data[dataPointer++];  // ^
                air_start = data[dataPointer++];  // Start of air run

                for (int i = 0; i < colourOffset; i++) {
                    drawBlock(x, air_start - colourOffset + i, z, colours[i]);
                }

                colourOffset = 0;

                for (int i = s; i < e + 1; i++) {
                    lastColour = getColour();
                    drawBlock(x, i, z, lastColour);
                }

                if (next == 0) break;

                for (int i = e - s + 1; i < next - 1; i++) {
                    colours[colourOffset] = getColour();
                    colourOffset += 1;
                }
            }

            for (int i = e + 1; i < yLength; i++) {
                drawBlock(x, i, z, lastColour);
            }
        }
    }

    return img;
}

SuperImage generatePreviewVXL(ubyte[] data) {
    return generatePreview(data, 512, 64, 512);
}

SuperImage generatePreviewIcemap(ubyte[] data) {

    uint dataPointer = ICEMAP_HEADER.length;
    auto dataLength = data.length;

    uint readVarInt() {
        ubyte first = data[dataPointer++];
        if (first < 0xFF) {
            return first;
        }
        return data[dataPointer++] + (data[dataPointer++] << 8) + (data[dataPointer++] << 16) + (data[dataPointer++] << 24);
    }

    uint read16() {
        return data[dataPointer++] + (data[dataPointer++] << 8);
    }

    // Check header
    if (data[0..ICEMAP_HEADER.length] != ICEMAP_HEADER) {
        // TODO: Fall back to VXL-compatability mode? Optional argument?
        // I don't currently have a file to test VXL fallback on, and I'm not sure if Iceball supports it atm anyway.
        throw new InvalidMapException("Not an Icemap v1 (missing header)");
    }

    while (true) {
        // TODO: Just catch RangeError over whole function and throw this? There are many other places we could OOB.
        if (dataPointer + 8 > dataLength) {
            throw new InvalidMapException("Reached end of file before end of map (partial file?)");
        }
        auto tag = data[dataPointer..dataPointer + 7];
        dataPointer += 7;
        uint chunkLength = readVarInt();
        if (tag == ICEMAP_TERMINATOR && chunkLength == 0) {
            break;
        } else if (tag == ICEMAP_TAG_MAP_DATA) {
            uint xLength = read16();
            uint yLength = read16();
            uint zLength = read16();
            auto mapData = data[dataPointer..dataPointer + chunkLength - 6];
            return generatePreview(mapData, xLength, yLength, zLength);
        } else {
            dataPointer += chunkLength;
        }
    }
    throw new InvalidMapException("No MapData section");
}

void drawMap(string inputFilename, string outputFilename) {
    ubyte[] data = cast(ubyte[])read(inputFilename);
    SuperImage img;
    if (inputFilename.toLower().endsWith(".vxl")) {
        img = generatePreviewVXL(data);
    } else {
        // Assume Icemap since it has (map spec does optionally, we don't yet) VXL compatability
        img = generatePreviewIcemap(data);
    }
    img.savePNG(outputFilename);
}
