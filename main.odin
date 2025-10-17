package main

import "core:bufio"
import "core:fmt"
import "core:math"
import "core:mem"
import os "core:os/os2"
import fp "core:path/filepath"
import sl "core:slice"
import "core:strconv"
import "core:strings"

PART_EXTENSION :: ".fsp"

SizeParserState :: enum {
	Start,
	Number,
	Unit,
	DecimalPoint,
	DecimalNumber,
}

SizeParserError :: enum {
	InvalidString,
	InvalidUnit,
}

Mode :: struct {
	workingDirectory: string,
	targetFile:       string,
	partSize:         i64,
	rebuild:          bool,
}

fractional_size :: proc(decimal: i64, factor: int, unit: i64) -> i64 {
	frac_size: f64 = f64(decimal) / math.pow(10, f64(factor))
	return i64(math.round(frac_size * f64(unit)))
}

parse_file_size :: proc(filesize: string) -> (size: i64, err: SizeParserError) {
	size = 0
	decimal: i64 = 0
	factor := 0
	state: SizeParserState = .Start
	for c in filesize {
		switch state {
		case .Start:
			if c >= '0' && c <= '9' {
				state = .Number
				size = i64(c - '0')
			} else {
				return 0, .InvalidString
			}
		case .Number:
			if c >= '0' && c <= '9' {
				size = size * 10 + i64(c - '0')
			} else if c == 'k' || c == 'K' {
				size *= mem.Kilobyte
				state = .Unit
			} else if c == 'm' || c == 'M' {
				size *= mem.Megabyte
				state = .Unit
			} else if c == 'g' || c == 'G' {
				size *= mem.Gigabyte
				state = .Unit
			} else if c == 't' || c == 'T' {
				size *= mem.Terabyte
				state = .Unit
			} else if c == '.' {
				state = .DecimalPoint
			} else {
				return 0, .InvalidString
			}
		case .Unit:
			return 0, .InvalidUnit
		case .DecimalPoint:
			if c >= '0' && c <= '9' {
				state = .DecimalNumber
				decimal = i64(c - '0')
				factor = 1
			} else {
				return 0, .InvalidString
			}
		case .DecimalNumber:
			if c >= '0' && c <= '9' {
				decimal = decimal * 10 + i64(c - '0')
				factor += 1
			} else if c == 'k' || c == 'K' {
				size *= mem.Kilobyte
				size += fractional_size(decimal, factor, mem.Kilobyte)
				state = .Unit
			} else if c == 'm' || c == 'M' {
				size *= mem.Megabyte
				size += fractional_size(decimal, factor, mem.Megabyte)
				state = .Unit
			} else if c == 'g' || c == 'G' {
				size *= mem.Gigabyte
				size += fractional_size(decimal, factor, mem.Gigabyte)
				state = .Unit
			} else if c == 't' || c == 'T' {
				size *= mem.Terabyte
				size += fractional_size(decimal, factor, mem.Terabyte)
				state = .Unit
			} else {
				return 0, .InvalidString
			}
		}
	}
	if state == .Unit || state == .Number {
		return size, nil
	}
	return 0, .InvalidString

}

parse_args :: proc(args: []string) -> (mode: Mode, ok: bool) {
	argc := len(args)
	pwd := fp.dir(args[0], context.temp_allocator)

	// FileSlicer <- rebuild in current directory
	if argc == 1 {
		reader: bufio.Reader
		bufio.reader_init(&reader, os.to_reader(os.stdin))
		defer bufio.reader_destroy(&reader)
		fmt.print("Enter the name for the output file: ")
		line, err := bufio.reader_read_string(&reader, '\n')
		if err != nil {
			fmt.println("Error on reading input:", err)
			return {}, false
		}
		trimmed := strings.trim(line, "\t\r\n ")
		if len(trimmed) == 0 {
			fmt.println("File name cannot be empty")
			return {}, false
		}
		mode.rebuild = true
		mode.targetFile = fp.join([]string{pwd, trimmed}, context.allocator)
		mode.workingDirectory = strings.clone(pwd, context.allocator)
		return mode, true
	}

	if argc == 4 {
		if args[1] == "-r" {
			// FileSlicer -r target/dir name.ext <- rebuild into file
			mode.rebuild = true
			mode.workingDirectory = fp.dir(args[2], context.allocator)
			mode.targetFile, _ = fp.join(
				[]string{mode.workingDirectory, args[3]},
				context.allocator,
			)
			return mode, true
		}
		// FileSlicer file.ext target/dir 50m <- slice file

		mode.rebuild = false
		mode.targetFile, _ = fp.join([]string{pwd, args[1]}, context.allocator)
		mode.workingDirectory = fp.dir(args[2], context.allocator)
		sizerr: SizeParserError
		mode.partSize, sizerr = parse_file_size(args[3])
		if sizerr != nil {
			fmt.println("Error on parsing the part size:", sizerr)
			return mode, false
		}
		return mode, true
	}

	return {}, false
}

main :: proc() {os.exit(run())}

run :: proc() -> int {
	mode, mode_ok := parse_args(os.args)
	defer {
		delete(mode.workingDirectory)
		delete(mode.targetFile)
	}
	if !mode_ok {
		show_invalid_arguments()
		return 1
	}

	if mode.rebuild {
		if !has_parts(mode.workingDirectory) {
			show_invalid_arguments()
			return 1
		}
		rebuild(mode.workingDirectory, mode.targetFile)
		fmt.println("File rebuilt:", mode.targetFile)
		delete_parts(mode.workingDirectory)
		return 0
	}

	slice(mode.targetFile, mode.workingDirectory, mode.partSize)
	fmt.println(
		"Sliced file:",
		mode.targetFile,
		"into:",
		mode.workingDirectory,
		"| part size:",
		mode.partSize,
		"B",
	)
	return 0
}

show_invalid_arguments :: proc() {
	msg :: `
=== [ USAGE ] ===
Slice:   FileSlicer [archive path] [destination directory] [size with unit]

	Example size values:
	 - 500 = 500 bytes
	 - 500k = 500 kilobytes
	 - 500m = 500 megabytes
	 - 500g = 500 gigabytes
	 - 500t = 500 terabytes
	Unit is case-insensitive (50k and 50K are the same size)
	You may also use fractional values with appropiate units (e.g. 2.5k, 3.3m)

Example: FileSlicer my.zip parts 10m
-----------------------
Rebuild: FileSlicer -r [directory with parts] [destination archive path]
         or just run FileSlicer in a folder with part files (.fsp) to auto rebuild
`


	fmt.println(msg)
}

has_parts :: proc(dirpath: string, allocator := context.allocator) -> bool {
	dir, err := os.open(dirpath)
	defer os.close(dir)
	if err != nil {
		return false
	}
	files, readerr := os.read_dir(dir, 0, allocator)
	defer os.file_info_slice_delete(files, allocator)
	if readerr != nil {
		return false
	}
	for fi in files {
		if fi.type == .Regular && fp.ext(fi.fullpath) == PART_EXTENSION {
			when ODIN_DEBUG {
				fmt.println("Found a file with given extension:", fi.fullpath)
			}
			return true
		}
	}
	return false
}

sort_parts_by_id :: proc(i, j: os.File_Info) -> bool {
	fi, fierr := os.open(i.fullpath)
	fj, fjerr := os.open(j.fullpath)
	defer {
		os.close(fi)
		os.close(fj)
	}
	if fierr != nil || fjerr != nil {
		return false
	}

	bi := [4]u8{}
	bj := [4]u8{}
	_, err := os.read_at(fi, bi[:], 0)
	_, err = os.read_at(fj, bj[:], 0)

	return transmute(i32)bi < transmute(i32)bj
}

rebuild :: proc(dirpath, zipfile: string, allocator := context.allocator) {
	parts := make([dynamic]os.File_Info)
	defer delete(parts)

	files: []os.File_Info
	{
		dir, err := os.open(dirpath)
		defer os.close(dir)
		if err != nil {
			return
		}
		files, err = os.read_dir(dir, 0, allocator)
		if err != nil {
			return
		}
	}
	defer os.file_info_slice_delete(files, allocator)
	for fi in files {
		when ODIN_DEBUG {
			fmt.println("examining", fi.fullpath)
		}
		if fi.type == .Regular && fp.ext(fi.fullpath) == PART_EXTENSION {
			when ODIN_DEBUG {
				fmt.println("adding", fi.fullpath)
			}
			append(&parts, fi)
		}
	}
	partslice := parts[:len(parts)]
	sl.sort_by(partslice, sort_parts_by_id)

	when ODIN_DEBUG {
		fmt.println("sorted files:")
		for fi in parts {
			fmt.println(fi.name)
		}
	}

	outfile, outerr := os.open(zipfile, os.File_Flags{.Write, .Create})
	defer os.close(outfile)
	if outerr != nil {
		fmt.println("Could not create file", zipfile, "-", outerr)
		return
	}

	for fi in partslice {
		when ODIN_DEBUG {
			fmt.println("Reading from", fi.fullpath, "...")
		}
		data, err := os.read_entire_file_from_path(fi.fullpath, allocator)
		defer delete(data, allocator)
		if err != nil {
			fmt.println("Could not read file", fi.fullpath, "-", err)
			return
		}

		if len(data) <= 4 {
			continue
		}

		_, err = os.write(outfile, data[4:])
		if err != nil {
			fmt.println("Could not write to file", outfile, "-", err)
			return
		}
	}

}

delete_parts :: proc(dirpath: string, allocator := context.allocator) {
	dir, err := os.open(dirpath)
	defer os.close(dir)
	if err != nil {
		return
	}
	files, readerr := os.read_dir(dir, 0, allocator)
	defer delete(files, allocator)
	if readerr != nil {
		return
	}
	for fi in files {
		if fi.type == .Regular && fp.ext(fi.fullpath) == PART_EXTENSION {
			rmerr := os.remove(fi.fullpath)
			if rmerr != nil {
				fmt.println("Could not remove", fi.name, "-", rmerr)
			}
		}
	}
}

slice :: proc(zipfile, dirpath: string, partsize: i64, allocator := context.allocator) {
	abspath, pathok := fp.abs(zipfile, allocator)
	defer delete(abspath)
	if !pathok {
		fmt.println("Could not derive abs path to", zipfile)
		return
	}

	fd, fileerr := os.open(zipfile)
	defer os.close(fd)

	if fileerr != nil {
		fmt.println("Could not open file", zipfile, "-", fileerr)
		return
	}

	offset: i64 = 0
	partid: i32 = 0

	buf := make([]u8, partsize, allocator)
	defer delete(buf, allocator)

	for {
		bytesread, readerr := os.read_at(fd, buf, offset)
		if readerr != nil && readerr != .EOF {
			fmt.println("Could not read file", zipfile, "-", readerr)
			return
		}
		offset += partsize
		part := buf[:bytesread]
		when ODIN_DEBUG {
			fmt.println("bytes read:", bytesread)
		}

		partname: string
		partname, fileerr = strings.concatenate(
			[]string {
				fp.join([]string{dirpath, fp.base(zipfile)}, context.temp_allocator),
				fmt.tprintf("_part_%d", partid),
				PART_EXTENSION,
			},
			context.temp_allocator,
		)

		if fileerr != nil {
			fmt.println("Error on creating file name -", fileerr)
			return
		}

		partfile, fileerr := os.open(partname, os.File_Flags{.Write, .Create})
		defer os.close(partfile)
		if fileerr != nil {
			fmt.println("Could not create file", partname, "-", fileerr)
			return
		}

		bufid := transmute([4]u8)partid

		byteswritten, writeerr := os.write(partfile, bufid[:])
		assert(byteswritten == 4, "write error")
		if writeerr != nil {
			fmt.println("Could not write to file", partname, "-", writeerr)
		}

		byteswritten, writeerr = os.write(partfile, part[:])
		assert(byteswritten == len(part), "write error")
		if writeerr != nil {
			fmt.println("Could not write to file", partname, "-", writeerr)
		}

		partid += 1
		if i64(bytesread) < partsize {
			break
		}
	}
}
