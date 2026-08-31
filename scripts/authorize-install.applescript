use scripting additions

on run argv
    if (count of argv) is not 2 then error "Expected installer and sudoers paths"
    set installerPath to item 1 of argv
    set sudoersPath to item 2 of argv
    set commandText to "/bin/zsh " & quoted form of installerPath & " " & quoted form of sudoersPath
    do shell script commandText with administrator privileges
end run
