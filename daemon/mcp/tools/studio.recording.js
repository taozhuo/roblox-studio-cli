/**
 * Recording Tools - Capture viewport frames and create videos/GIFs
 */

import { spawn } from 'child_process';
import fs from 'fs/promises';
import path from 'path';
import os from 'os';

// Recording state
let isRecording = false;
let recordingInterval = null;
let frames = [];
let recordingStartTime = 0;

// Temp directory for frames
const TEMP_DIR = path.join(os.tmpdir(), 'bakable-recording');

export function registerRecordingTools(registerTool, callPlugin) {
  // Start recording viewport
  registerTool('studio.recording.start', {
    description: 'Start recording viewport frames. Captures screenshots at the specified FPS for later assembly into a video or GIF.',
    inputSchema: {
      type: 'object',
      properties: {
        fps: {
          type: 'number',
          description: 'Frames per second to capture (default: 10, max: 30)',
        },
        maxDuration: {
          type: 'number',
          description: 'Maximum recording duration in seconds (default: 30)',
        },
      },
    },
  }, async ({ fps = 10, maxDuration = 30 }) => {
    if (isRecording) {
      return { error: 'Already recording. Stop current recording first.' };
    }

    // Ensure temp directory exists
    await fs.mkdir(TEMP_DIR, { recursive: true });

    // Clear any existing frames
    frames = [];
    isRecording = true;
    recordingStartTime = Date.now();

    const interval = 1000 / Math.min(fps, 30);

    recordingInterval = setInterval(async () => {
      // Check max duration
      if ((Date.now() - recordingStartTime) / 1000 > maxDuration) {
        clearInterval(recordingInterval);
        recordingInterval = null;
        console.log(`[Recording] Max duration (${maxDuration}s) reached`);
        return;
      }

      try {
        // Capture viewport from plugin
        const result = await callPlugin('studio.captureViewport', {});
        if (result && result.base64) {
          const frameNum = frames.length;
          const framePath = path.join(TEMP_DIR, `frame_${String(frameNum).padStart(5, '0')}.png`);

          // Decode base64 and save
          const buffer = Buffer.from(result.base64, 'base64');
          await fs.writeFile(framePath, buffer);

          frames.push({
            path: framePath,
            timestamp: Date.now() - recordingStartTime,
          });

          console.log(`[Recording] Captured frame ${frameNum + 1}`);
        }
      } catch (err) {
        console.error(`[Recording] Error capturing frame: ${err.message}`);
      }
    }, interval);

    return {
      started: true,
      fps: Math.min(fps, 30),
      maxDuration,
      tempDir: TEMP_DIR,
    };
  });

  // Stop recording
  registerTool('studio.recording.stop', {
    description: 'Stop recording viewport and return frame info.',
    inputSchema: {
      type: 'object',
      properties: {},
    },
  }, async () => {
    if (!isRecording) {
      return { error: 'Not currently recording' };
    }

    if (recordingInterval) {
      clearInterval(recordingInterval);
      recordingInterval = null;
    }

    isRecording = false;
    const duration = (Date.now() - recordingStartTime) / 1000;

    return {
      stopped: true,
      frameCount: frames.length,
      duration: duration.toFixed(2),
      tempDir: TEMP_DIR,
    };
  });

  // Get recording status
  registerTool('studio.recording.status', {
    description: 'Get current recording status.',
    inputSchema: {
      type: 'object',
      properties: {},
    },
  }, async () => {
    const duration = isRecording ? (Date.now() - recordingStartTime) / 1000 : 0;

    return {
      isRecording,
      frameCount: frames.length,
      duration: duration.toFixed(2),
    };
  });

  // Create GIF from recorded frames
  registerTool('studio.recording.createGif', {
    description: 'Create a GIF from recorded frames. Requires ffmpeg to be installed.',
    inputSchema: {
      type: 'object',
      properties: {
        outputPath: {
          type: 'string',
          description: 'Output path for the GIF file (default: ~/Desktop/recording.gif)',
        },
        fps: {
          type: 'number',
          description: 'FPS for the output GIF (default: 10)',
        },
        width: {
          type: 'number',
          description: 'Width of output GIF in pixels (default: 480)',
        },
      },
    },
  }, async ({ outputPath, fps = 10, width = 480 }) => {
    if (frames.length === 0) {
      return { error: 'No frames recorded. Start and stop a recording first.' };
    }

    if (isRecording) {
      return { error: 'Recording in progress. Stop recording first.' };
    }

    const output = outputPath || path.join(os.homedir(), 'Desktop', 'recording.gif');

    // Use ffmpeg to create GIF
    const inputPattern = path.join(TEMP_DIR, 'frame_%05d.png');

    return new Promise((resolve) => {
      // ffmpeg command to create GIF with palette for better quality
      const proc = spawn('ffmpeg', [
        '-y', // Overwrite output
        '-framerate', String(fps),
        '-i', inputPattern,
        '-vf', `fps=${fps},scale=${width}:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse`,
        '-loop', '0', // Loop forever
        output,
      ]);

      let stderr = '';
      proc.stderr.on('data', (data) => {
        stderr += data.toString();
      });

      proc.on('close', (code) => {
        if (code === 0) {
          resolve({
            success: true,
            output,
            frameCount: frames.length,
            width,
            fps,
          });
        } else {
          resolve({
            error: `ffmpeg failed with code ${code}`,
            details: stderr.substring(stderr.length - 500),
          });
        }
      });

      proc.on('error', (err) => {
        resolve({
          error: `ffmpeg not found. Install with: brew install ffmpeg`,
          details: err.message,
        });
      });
    });
  });

  // Create MP4 video from recorded frames
  registerTool('studio.recording.createVideo', {
    description: 'Create an MP4 video from recorded frames. Requires ffmpeg to be installed.',
    inputSchema: {
      type: 'object',
      properties: {
        outputPath: {
          type: 'string',
          description: 'Output path for the MP4 file (default: ~/Desktop/recording.mp4)',
        },
        fps: {
          type: 'number',
          description: 'FPS for the output video (default: 30)',
        },
      },
    },
  }, async ({ outputPath, fps = 30 }) => {
    if (frames.length === 0) {
      return { error: 'No frames recorded. Start and stop a recording first.' };
    }

    if (isRecording) {
      return { error: 'Recording in progress. Stop recording first.' };
    }

    const output = outputPath || path.join(os.homedir(), 'Desktop', 'recording.mp4');
    const inputPattern = path.join(TEMP_DIR, 'frame_%05d.png');

    return new Promise((resolve) => {
      const proc = spawn('ffmpeg', [
        '-y',
        '-framerate', String(fps),
        '-i', inputPattern,
        '-c:v', 'libx264',
        '-pix_fmt', 'yuv420p',
        '-crf', '23',
        output,
      ]);

      let stderr = '';
      proc.stderr.on('data', (data) => {
        stderr += data.toString();
      });

      proc.on('close', (code) => {
        if (code === 0) {
          resolve({
            success: true,
            output,
            frameCount: frames.length,
            fps,
          });
        } else {
          resolve({
            error: `ffmpeg failed with code ${code}`,
            details: stderr.substring(stderr.length - 500),
          });
        }
      });

      proc.on('error', (err) => {
        resolve({
          error: `ffmpeg not found. Install with: brew install ffmpeg`,
          details: err.message,
        });
      });
    });
  });

  // Clear recorded frames
  registerTool('studio.recording.clear', {
    description: 'Clear all recorded frames and free up disk space.',
    inputSchema: {
      type: 'object',
      properties: {},
    },
  }, async () => {
    if (isRecording) {
      return { error: 'Cannot clear while recording. Stop recording first.' };
    }

    const frameCount = frames.length;

    // Delete all frame files
    for (const frame of frames) {
      try {
        await fs.unlink(frame.path);
      } catch (e) {
        // Ignore errors
      }
    }

    frames = [];

    return {
      cleared: true,
      framesRemoved: frameCount,
    };
  });

  console.error('[MCP] Recording tools registered');
}
