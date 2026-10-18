   return size;
}

bool retro_serialize(void *data, size_t size)
{
   void *buffer;
   size_t out_size;

   ScspMuteAudio(SCSP_MUTE_SYSTEM);
   int error = YabSaveStateBuffer (&buffer, &out_size);
   ScspUnMuteAudio(SCSP_MUTE_SYSTEM);

   memcpy(data, buffer, size);

   free(buffer);

   return !error;
}

bool retro_unserialize(const void *data, size_t size)
{
   ScspMuteAudio(SCSP_MUTE_SYSTEM);
