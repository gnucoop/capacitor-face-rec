/**
 * Copyright (C) 2019 Gnucoop soc. coop.
 *
 * This file is part of c2s.
 *
 * c2s is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * c2s is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with c2s.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

import { FaceRecGetPhotoOpts } from './get-photo-opts';
import { FaceRecInitEvent } from './init-event';
import { FaceRecInitOpts } from './init-opts';
import { FaceRecognitionResult } from './result';

declare module '@capacitor/core' {
  interface PluginRegistry {
    FaceRec: FaceRecPlugin;
  }
}

export interface FaceRecPlugin {
  initFaceRecognition(opts: FaceRecInitOpts): Promise<FaceRecInitEvent>;
  getPhoto(opts: FaceRecGetPhotoOpts): Promise<FaceRecognitionResult>;
  addEventListener(event: 'faceRecInitStatusChanged', handler: (statusEvt: FaceRecInitEvent) => void): void;
  removeEventListener(event: 'faceRecInitStatusChanged', handler: (statusEvt: FaceRecInitEvent) => void): void;
}
