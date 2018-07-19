/* P2-va-class.h

Virtual array class.  Everything you need for stand alone access to file data.
*/

#include <stdio.h>
#include <stdlib.h>


class VirtualArray
{
    private:
           int size_of_slice;  // input from user
           int size_of_file;  //calculated
	   int number_of_slices //in a file (calculated)

	     public:
	   //constructors
	   // open source file submitted by client (program)
	   if((vArray-source = fopen varray-src, "rb")==NULL)
	     {
	       printf ("Cannot open source file to read from."\n);
	       //this should be returned to client (program)
	     }

// open dest file submitted by client (program)
	   if((vArray-dest = fopen varray-dest, "wb")==NULL)
	     {
	       printf ("Cannot open destination file to write to."\n);
	       //this should be returned to client (program)
	     }









}


/*

slice size will be passed from client
find size of file 
input file name  will be passed from client
output file name  will be passed from client
divide file size (size of array) by size-of-slice (to find location)
read first slice (number of bytes/int asked for earlier)
ask what slice (again)
       decode weather to go forward or backwards
set something if the slice is/was changed
variable needed to find local slice (location)





*/
