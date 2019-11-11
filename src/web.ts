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

import { WebPlugin, registerWebPlugin } from '@capacitor/core';
import { FaceRecPlugin } from './definitions';
import { FaceRecGetPhotoOpts } from './get-photo-opts';
import { FaceRecInitEvent } from './init-event';
import { FaceRecInitStatus } from './init-status';
import { FaceRecInitStatusChangeHandler } from './init-status-change-handler';
import { FaceRecognitionResult } from './result';

export class FaceRecWeb extends WebPlugin implements FaceRecPlugin {
  private _events: {[key: string]: FaceRecInitStatusChangeHandler[]} = {};

  constructor() {
    super({
      name: 'FaceRec',
      platforms: ['web']
    });
  }

  initFaceRecognition(_opts: {modelUrl: string}): Promise<FaceRecInitEvent> {
    const evt = { status: FaceRecInitStatus.Success };
    (this._events['faceRecInitStatusChanged'] || []).forEach(h => h(evt));
    return Promise.resolve(evt);
  }

  getPhoto(_opts: FaceRecGetPhotoOpts): Promise<FaceRecognitionResult> {
    return Promise.resolve({
      faces: [],
      originalImage: '', taggedImage: { base64Data: '' }
    });
  }

  addListener(event: 'faceRecInitStatusChanged', handler: FaceRecInitStatusChangeHandler): {remove: () => void} {
    if (this._events[event] == null) {
      this._events[event] = [];
    }
    this._events[event].push(handler);
    return {remove: () => this._removeListener(event, handler)};
  }

  private _removeListener(event: 'faceRecInitStatusChanged', handler: FaceRecInitStatusChangeHandler): void {
    if (this._events[event] == null) { return; }
    const hIdx = this._events[event].indexOf(handler);
    if (hIdx > -1) {
      this._events[event].splice(hIdx, 1);
    }
  }
}

const FaceRec = new FaceRecWeb();

export { FaceRec };

registerWebPlugin(FaceRec);
