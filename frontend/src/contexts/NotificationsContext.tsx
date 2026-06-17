/**
 * Copyright (c) 2025, WSO2 LLC. (https://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

import { createContext, useContext, type JSX, type ReactNode } from 'react';
import { useNotifications, type NotificationItem, type UseNotificationsReturn } from '@wso2/oxygen-ui';

type NotificationsContextValue = UseNotificationsReturn & {
  addNotification: (notification: Omit<NotificationItem, 'id'>) => void;
};

const NotificationsContext = createContext<NotificationsContextValue | null>(null);

export function NotificationsProvider({ children }: { children: ReactNode }): JSX.Element {
  const notif = useNotifications();
  console.log('[NotificationsProvider] mounted, actions:', Object.keys(notif.actions));
  return <NotificationsContext.Provider value={{ ...notif, addNotification: notif.actions.add }}>{children}</NotificationsContext.Provider>;
}

export function useNotificationsContext(): NotificationsContextValue {
  const ctx = useContext(NotificationsContext);
  if (!ctx) throw new Error('useNotificationsContext must be used within NotificationsProvider');
  return ctx;
}
