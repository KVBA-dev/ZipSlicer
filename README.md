# ZipSlicer

A simple tool that lets you split large ZIP archives into smaller parts — or merge them back into the original file.\
Great for sending large files over Discord or other messengers that limit file size.

## Building
1. Install Odin compiler
2. Run following command
```
odin build . -out:ZipSlicer
```

## Usage

### - Slicing

```
ZipSlicer [zip path] [destination directory path] [part size]
```
or

```
ZipSlicer [destination directory path] [zip path] [part size]
```

Example:
```
ZipSlicer largeArchive.zip destinationPath 5m
```

### - Merging

```
ZipSlicer.exe -r [directory with parts] [destination archive path]
```
>[!IMPORTANT]
or simply **double-click the program file** in the same directory as the other parts.

