# sln-make
 Extends the CMake generation applying settings to a Visual Studio solution based on a text configuration file.

<br>

## Why?

<br>

CMake is great, but you can't generate a Visual Studio solution with many settings pre-applied, such as macros and directories, since there exist no commands to do that.
\
\
And that's fine, some properties are just too IDE specific and maybe should not be part of CMake job, but of a specialized tool.
\
\
Furthermore, some properties set with `set_property` will not be overridden if you call the command twice or more on the same property. And some commands like `add_custom_command` just append stuff and do not provide an option to override or reset previous calls.
\
\
That's not an unjustified behavior, but if you find yourself using an SDK or some external cmake files that call functions not under your control, that in turn call those aforementioned non-ovverridable commands, you can't just override some settings without modifying the actual SDK code under the hood.
\
\
And you obviously shouldn't.
\
Besides, not everyone has the same settings style.

<br>

### Introducing **sln-make**

<br>

Just leave everything as it is and place a `sln-make.inix` in the project root directory.
\
After generating the solution with CMake, then call `sln-make` on the project root, and it will apply the settings specified in the `sln-make.inix` file to the solution.
\
\
If you change the settings in `sln-make.inix`, you can re-run `sln-make`, but a CMakeCache, must be present, as the solution will be regenerated first thing first.
\
\
Just as with CMake you know you can generate a Visual Studio solution anytime anywhere,
with **sln-make** you will be sure to have your Visual Studio settings with you, anytime, anywhere. 

<br>

## Usage

<br>

Here's an [example project structure](example-project), with an [sln-make.inix](example-project/sln-make.inix) showing the syntax and all the options currently available.
\
\
Place `sln-make.inix` in the project root directory (which contains source files, assets, etc...) just as you did with `CMakeLists.txt`.
\
\
Run `sln-make.ps1 -projectRootDir path/to/project-root-directory`
>you can just run it without specifying `projectRootDir` and it will assume that the project root directory is the current working directory

<br>

Depending on how you're running the script you may want to keep the console open: use `-keepOpen` .

<br>

`add_to_path.ps1` simply adds the current folder to `PATH`, so you can call `sln-make` from anywhere.

<br>


### Internally

<br>

1. It will try to delete the `.vs` folder, as Visual Studio may cache some settings, ensuring a fresh start.

2. It will call **cmake** automatically to regenerate the solution, ensuring a fresh start. 
\
For this reason you must have already configured cmake and generated the solution, and the CMakeCache must be present.
3. After checking that the files and the mandatory options are present, it will apply the settings to the solution files. 
4. If anything went wrong it should tell you.

<br>

## Contributing

<br>

This tool is experimental and it's not complete in any way.
\
Any contribution making it more useful and stable is very much appreciated.

<br>

### [License](LICENSE)