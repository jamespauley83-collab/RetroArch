
//////////////////////////////////////////////////////////////////////////////

int YabSaveStateBuffer(void ** buffer, size_t * size)
{
   int status;

   // Reset buffer & size if needed
   if (buffer != NULL) *buffer = NULL;
   *size = 0;

   status = YabSaveStateStream(NULL);
   if (status != 0)
      return status;

   *size = MemStateGetOffset();

   if (buffer != NULL)
   {
      *buffer = malloc(*size);
      if (*buffer == NULL)
         return -1;

      status = YabSaveStateStream(buffer);
   }

   return 0;
}

//////////////////////////////////////////////////////////////////////////////

int YabSaveState(const char *filename)
