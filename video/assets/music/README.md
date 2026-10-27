# Music

- `bed.mp3`: the film's bed. Generated with the ElevenLabs Music API on 2026-10-27 from `plan.json` (catchy, 120 BPM), then edited to the film: the take starts at 9.951 s so its drop lands on the title at 6.0 s, the 8-second phrase from 23.951 s plays twice, and the 4-second phrase from 31.951 s plays twice, so the ending lands at 43 s (the groove repeats every 4 s, correlation 0.87–0.92).

  ```
  ffmpeg -i take.mp3 -filter_complex "[0:a]atrim=start=9.951:end=31.971,asetpts=PTS-STARTPTS,afade=t=in:d=0.25[a];[0:a]atrim=start=23.951:end=35.971,asetpts=PTS-STARTPTS[b];[0:a]atrim=start=31.951:end=43.0,asetpts=PTS-STARTPTS[c];[a][b]acrossfade=d=0.02:c1=tri:c2=tri[ab];[ab][c]acrossfade=d=0.02:c1=tri:c2=tri[o]" -map "[o]" -b:a 192k bed.mp3
  ```

  The film's beat grid falls every 0.5 s from 0 (downbeats every 2 s), so 6, 9, 28 and 34 s land on beats.
- `bed-calm.mp3` / `plan-calm.json`: the first, calmer bed (100 BPM piano), kept as an alternative.

Usage rights follow the ElevenLabs plan of the account that generated them.
