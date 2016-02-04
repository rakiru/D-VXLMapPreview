module vxlimagegen;

// TODO: Explicit/selective imports, as soon as I figure out why "private import std.uni : toLower" exports toLower publically...
// Oh, turns out it's an ancient bug that has yet to be fixed. That sure makes me want to invest in learning the language... <_<
// https://issues.dlang.org/show_bug.cgi?id=314
import std.algorithm.searching;
import std.conv;
import std.file;
import std.format;
import std.math;
import std.stdio;
import std.uni;

import dlib.image;
import dlib.image.io.png;

private const string ICEMAP_HEADER = "IceMap\x1A\x01";
private const string ICEMAP_TAG_MAP_DATA = "MapData";
private const string ICEMAP_TERMINATOR = "       ";

private struct BlockColour {
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

// Thanks to Jagex for breaking the map format in AoS 1.0 and requiring us to parse the map twice!!!111
private void computeMapSize(const ubyte[] data, ref uint xLength, ref uint yLength, ref uint zLength) {

    uint columns = 0;
    uint maxHeight = 0;
    uint dataPointer = 0;
    immutable dataLength = data.length;

    while (dataPointer + 3 < dataLength) {

        ubyte next;
        ubyte s;
        ubyte e;

        // Loop through the data until we reach the end of the pillar
        while (dataPointer + 3 < dataLength) {

            // Read control entity
            // Bypass builtin bounds checking for performance (while loop ensures we're safe already)
            next = data.ptr[dataPointer++];  // Distance to next control block, 0 if no more
            s = data.ptr[dataPointer++];  // Start of floor colour run
            e = data.ptr[dataPointer++];  // ^
            dataPointer++;  // Start of air run, not needed here

            if (e > maxHeight) maxHeight = e;

            dataPointer += (e - s + 1) * 4;

            if (next == 0) break;

            dataPointer += (next - (e - s) - 2) * 4;
        }

        columns++;
    }
    xLength = cast(uint)sqrt(float(columns));
    zLength = xLength;
    yLength = maxHeight + 1;
}

// TODO: Figure out way to use ImageRGB8 instead of ImageRGBA8 if backgroundColour.a == 255 (waste of space in files)
// Most of the function would be the same, (pixelSize already deals with the size different), it's just the alpha
// channel writes that would need to be removed. Can we create two versions of this function from some sort of template?
SuperImage generatePreview(const ubyte[] data, uint xLength, uint yLength, uint zLength, Colour backgroundColour) {

    if (yLength == 0 || xLength == 0 || zLength == 0) {
        computeMapSize(data, xLength, yLength, zLength);
        debug {
            writeln("Calculated map size: %s, %s, %s".format(xLength, yLength, zLength));
        }
    }

    uint dataPointer = 0;
    immutable dataLength = data.length;
    immutable uint imgWidth = (xLength + zLength) * 2;
    immutable uint imgHeight = (xLength + zLength) + (yLength * 2);

    SuperImage img = new ImageRGBA8(imgWidth, imgHeight);
    // We have to operate on the raw data because the setPixel mathod is private,
    // and the index operator only works on floats. <_<
    auto imgData = img.data;
    immutable imgDataLength = imgData.length;
    immutable pixelSize = img.pixelSize;
    assert(pixelSize >= 4);

    BlockColour[] colours;
    colours.length = yLength;
    uint colourOffset = 0;

    BlockColour getColour() {
        if (dataPointer + 3 >= dataLength) {
            throw new InvalidMapException("Reached end of file before end of map (partial file?)");
        }
        auto colour = BlockColour(
            data.ptr[dataPointer++],
            data.ptr[dataPointer++],
            data.ptr[dataPointer++]
        );
        dataPointer++;  // "Light"
        return colour;
    }

    void drawBlock(uint x, uint y, uint z, BlockColour colour) {
        immutable uint rx = (z - x) * 2 + (imgWidth / 2);
        immutable uint ry = x + z + (y * 2);
        for (int i = 0; i < 2; i++) {
            immutable uint ii = (((ry + i) * imgWidth) + rx) * pixelSize;
            if (ii + pixelSize + 3 >= imgDataLength) {
                throw new InvalidMapException("Attempted to draw out of bounds blocks");
            }
            for (int j = 0; j < 2 * pixelSize; j += pixelSize) {
                immutable p = ii + j;
                imgData.ptr[p] = colour.r;
                imgData.ptr[p + 1] = colour.g;
                imgData.ptr[p + 2] = colour.b;
                imgData.ptr[p + 3] = 255;
            }
        }
    }

    for (int i = 0; i < imgDataLength; i += pixelSize) {
        imgData.ptr[i] = backgroundColour.r;
        imgData.ptr[i + 1] = backgroundColour.g;
        imgData.ptr[i + 2] = backgroundColour.b;
        imgData.ptr[i + 3] = backgroundColour.a;
    }

    for (int x = 0; x < zLength; x++) {
        for (int z = 0; z < xLength; z++) {

            ubyte next;
            ubyte s;
            ubyte e;
            ubyte air_start;
            BlockColour lastColour = {0, 0, 0};

            // Loop through the data until we reach the end of the pillar
            while (true) {

                if (dataPointer + 3 >= dataLength) {
                    throw new InvalidMapException("Reached end of file before end of map (partial file?)");
                }

                // Read control entity
                next = data.ptr[dataPointer++];  // Distance to next control block, 0 if no more
                s = data.ptr[dataPointer++];  // Start of floor colour run
                e = data.ptr[dataPointer++];  // ^
                air_start = data.ptr[dataPointer++];  // Start of air run

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

SuperImage generatePreviewVXL(const ubyte[] data, Colour backgroundColour) {
    return generatePreview(data, 0, 0, 0, backgroundColour);
}

SuperImage generatePreviewIcemap(const ubyte[] data, Colour backgroundColour, bool vxlFallback=true) {

    uint dataPointer = ICEMAP_HEADER.length;
    immutable dataLength = data.length;

    uint readVarInt() {
        if (dataPointer >= dataLength) {
            throw new InvalidMapException("Reached end of file before end of map (partial file?)");
        }
        ubyte first = data.ptr[dataPointer++];
        if (first < 0xFF) {
            return first;
        }
        if (dataPointer + 3 >= dataLength) {
            throw new InvalidMapException("Reached end of file before end of map (partial file?)");
        }
        return data.ptr[dataPointer++] + (data.ptr[dataPointer++] << 8) + (data.ptr[dataPointer++] << 16) + (data.ptr[dataPointer++] << 24);
    }

    uint read16() {
        if (dataPointer + 1 >= dataLength) {
            throw new InvalidMapException("Reached end of file before end of map (partial file?)");
        }
        return data.ptr[dataPointer++] + (data.ptr[dataPointer++] << 8);
    }

    // Check header
    if (data[0..ICEMAP_HEADER.length] != ICEMAP_HEADER) {
        // Note: Untested as I don't have such a file on hand.
        if (vxlFallback) {
            debug {
                writeln("Falling back to VXL mode");
            }
            return generatePreview(data, 512, 64, 512, backgroundColour);
        } else {
            throw new InvalidMapException("Not an Icemap v1 (missing header)");
        }
    }

    while (true) {
        if (dataPointer + 7 >= dataLength) {
            throw new InvalidMapException("Reached end of file before end of map (partial file?)");
        }
        const auto tag = data.ptr[dataPointer..dataPointer + 7];
        dataPointer += 7;
        uint chunkLength = readVarInt();
        if (tag == ICEMAP_TERMINATOR && chunkLength == 0) {
            break;
        } else if (tag == ICEMAP_TAG_MAP_DATA) {
            immutable uint xLength = read16();
            immutable uint yLength = read16();
            immutable uint zLength = read16();
            if (dataPointer + chunkLength - 6 >= dataLength) {
                throw new InvalidMapException("Reached end of file before end of map (partial file?)");
            }
            auto mapData = data[dataPointer..dataPointer + chunkLength - 6];
            return generatePreview(mapData, xLength, yLength, zLength, backgroundColour);
        } else {
            dataPointer += chunkLength;
        }
    }
    throw new InvalidMapException("No MapData section");
}

void drawMap(string inputFilename, string outputFilename, Colour backgroundColour=Colour(0, 0, 0, 255)) {
    ubyte[] data = cast(ubyte[])read(inputFilename);
    SuperImage img;
    if (inputFilename.toLower().endsWith(".vxl")) {
        img = generatePreviewVXL(data, backgroundColour);
    } else {
        // Assume Icemap since it has (map spec does optionally, we don't yet) VXL compatability
        img = generatePreviewIcemap(data, backgroundColour);
    }
    img.savePNG(outputFilename);
}

// TODO: Organisation - split utils things into different file
public struct Colour {
    ubyte r;
    ubyte g;
    ubyte b;
    ubyte a = 255;
}

class InvalidColourException : Exception {
    public {
        @safe pure nothrow this(string message, string file=__FILE__, size_t line=__LINE__, Throwable next=null) {
            super(message, file, line, next);
        }
        @safe pure nothrow this(string message, Throwable next, string file=__FILE__, size_t line=__LINE__) {
            super(message, file, line, next);
        }
    }
}

public Colour parseColourString(string colourString) {

    colourString = colourString.toLower();
    if (colourString.startsWith("0x")) {
        colourString = colourString[2..colourString.length];
    }

    ubyte getValue(immutable uint position) {
        ubyte total = 0;
        foreach (c; colourString[position * 2..position * 2 + 2]) {
            total <<= 4;
            if (c >= '0' && c <= '9') {
                total += c - '0';
            } else if (c >= 'a' && c <= 'f') {
                total += c - 'a' + 10;
            } else {
                throw new InvalidColourException("Colour must be a hex string in format RGB or RGBA");
            }
        }
        return total;
    }

    immutable len = colourString.length;
    Colour colour;
    if (len != 6 && len != 8) {
        throw new InvalidColourException("Colour must be a hex string in format RGB or RGBA");
    }

    colour.r = getValue(0);
    colour.g = getValue(1);
    colour.b = getValue(2);
    if (len == 8) {
        colour.a = getValue(3);
    }
    return colour;
}
