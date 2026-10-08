-- Print Label: Finder right-click > Open With > Print Label, or double-click to choose a PDF.
-- Runs print-label on the default printer with its default settings.
on open theFiles
	repeat with f in theFiles
		set p to POSIX path of f
		set n to do shell script "basename " & quoted form of p
		try
			do shell script "\"$HOME/.local/bin/print-label\" " & quoted form of p
			display notification "Barcode verified and sent to the printer." with title ("Printed " & n)
		on error errMsg
			display alert ("Couldn't print " & n) message errMsg as critical
		end try
	end repeat
end open

on run
	set f to choose file of type {"com.adobe.pdf"} with prompt "Choose a shipping label PDF to print"
	open {f}
end run
